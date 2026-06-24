//
//  SpooferServiceLive.swift
//  SpooferService
//
//  Live SpooferClient over GoIOSKit. Owns a per-device userspace tunnel and a held
//  location session (set-location for teleport, GPX playback for navigation). Root-free.
//

import Foundation
import GoIOSKit
import Logging
import Models
import SpooferInterface

public actor SpooferServiceLive: SpooferClient {
    private let goios: GoIOS?
    private var tunnels: [String: GoIOSTunnel] = [:]
    private var sessions: [String: GoIOSLocationSession] = [:]
    private var navigationTasks: [String: Task<Void, Never>] = [:]

    public init() {
        goios = try? GoIOS()
    }

    private func requireGoios() throws -> GoIOS {
        guard let goios else { throw SpooferError.backendUnavailable }
        return goios
    }

    // MARK: - SpooferClient

    public func connectedDevices() async throws -> [SpoofDevice] {
        let goios = try requireGoios()
        let udids = try await goios.listDeviceUDIDs()
        var devices: [SpoofDevice] = []
        for udid in udids {
            guard let info = try? await goios.info(udid: udid) else { continue }
            devices.append(SpoofDevice(
                id: info.udid,
                name: info.name,
                version: info.version,
                productType: info.productType,
                connectionType: Self.map(info.connectionType)
            ))
        }
        return devices
    }

    public func prepare(deviceID: String) async throws {
        let goios = try requireGoios()
        let tunnel = tunnels[deviceID] ?? GoIOSTunnel(goios: goios, udid: deviceID)
        tunnels[deviceID] = tunnel
        do {
            try await Self.offActor { try tunnel.start() }
        } catch let error as GoIOSError {
            throw Self.mapTunnel(error)
        }
        do {
            try await goios.mountDeveloperImage(udid: deviceID)
        } catch let error as GoIOSError {
            throw SpooferError.developerImageFailed(error.description)
        }
        Log.info("Spoofer prepared for \(deviceID)")
    }

    public func setLocation(deviceID: String, to coordinate: Coordinate) async throws {
        _ = try requireGoios()
        cancelNavigation(deviceID: deviceID)
        let session = try session(for: deviceID)
        // No explicit endpoint: let go-ios auto-discover the tunnel (matches the working
        // AppKit build). Passing --address/--rsd-port made setlocation hang on-device.
        do {
            try await Self.offActor {
                try session.setLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        } catch let error as GoIOSError {
            throw Self.mapLocation(error)
        }
    }

    public func navigate(deviceID: String, route: [Coordinate], speed: MovementSpeed) async throws {
        _ = try requireGoios()
        let session = try session(for: deviceID)
        // Step `setlocation` along interpolated points (the proven teleport path), letting
        // go-ios auto-discover the tunnel — NO explicit endpoint (that made it hang).
        let (points, dt) = GPXRouteBuilder.resampledRoute(route: route, speed: speed)
        cancelNavigation(deviceID: deviceID)
        guard points.count > 1 else {
            if let first = points.first {
                try? await Self.offActor {
                    try session.step(latitude: first.latitude, longitude: first.longitude)
                }
            }
            return
        }
        let intervalNanos = UInt64(max(dt, 0.05) * 1_000_000_000)
        let task = Task { [weak self] in
            for point in points {
                if Task.isCancelled { return }
                try? await Self.offActor {
                    try session.step(latitude: point.latitude, longitude: point.longitude)
                }
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
            await self?.finishNavigation(deviceID: deviceID)
        }
        navigationTasks[deviceID] = task
    }

    public func reset(deviceID: String) async throws {
        cancelNavigation(deviceID: deviceID)
        // Stopping the held session closes the DVT simulate-location connection, which
        // reverts the device to its real GPS. (A fresh `resetlocation` invocation can't
        // reliably find the tunnel — same issue as setlocationgpx — so we don't use it.)
        sessions[deviceID]?.stop()
    }

    public func shutdown(deviceID: String) async {
        cancelNavigation(deviceID: deviceID)
        sessions[deviceID]?.stop()
        sessions[deviceID] = nil
        tunnels[deviceID]?.stop()
        tunnels[deviceID] = nil
    }

    // MARK: - Helpers

    private func session(for deviceID: String) throws -> GoIOSLocationSession {
        let goios = try requireGoios()
        if let existing = sessions[deviceID] { return existing }
        let session = GoIOSLocationSession(goios: goios, udid: deviceID)
        sessions[deviceID] = session
        return session
    }

    /// Cancel an in-flight navigation (stepping loop) for the device, if any.
    private func cancelNavigation(deviceID: String) {
        navigationTasks[deviceID]?.cancel()
        navigationTasks[deviceID] = nil
    }

    /// Called by a navigation task that ran to completion (so we don't drop a still-running one).
    private func finishNavigation(deviceID: String) {
        navigationTasks[deviceID] = nil
    }

    /// Run a blocking GoIOSKit call off the actor so we never stall the actor's executor.
    private static func offActor(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try work(); continuation.resume() } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func map(_ type: GoIOSConnectionType) -> SpoofDevice.ConnectionType {
        switch type {
        case .usb: return .usb
        case .network: return .network
        case .unknown: return .unknown
        }
    }

    private static func mapTunnel(_ error: GoIOSError) -> SpooferError {
        if case .binaryNotFound = error { return .backendUnavailable }
        return .tunnelFailed(error.description)
    }

    private static func mapLocation(_ error: GoIOSError) -> SpooferError {
        switch error {
        case .binaryNotFound: return .backendUnavailable
        case .tunnelNotRunning: return .tunnelFailed("tunnel not running")
        default: return .locationFailed(error.description)
        }
    }
}
