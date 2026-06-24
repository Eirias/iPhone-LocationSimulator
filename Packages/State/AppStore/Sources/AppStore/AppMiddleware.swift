//
//  AppMiddleware.swift
//  AppStore
//
//  Async side effects: device discovery, tunnel preparation, location set/navigate/reset.
//  Route computation (MapKit directions) happens here so the views stay declarative.
//

import Foundation
import Logging
import MapKit
import Models
import Redux
import SpooferInterface

public struct AppMiddleware: Middleware {
    private let spoofer: SpooferClient

    public init(spoofer: SpooferClient) {
        self.spoofer = spoofer
    }

    public func process(state: AppState, action: AppEvent) async -> AppEvent? {
        switch action {
        case .onAppear, .refreshDevices:
            do {
                return try .devicesLoaded(await spoofer.connectedDevices())
            } catch SpooferError.backendUnavailable {
                return .backendUnavailable
            } catch {
                return .failed("\(error)")
            }

        case let .selectDevice(deviceID):
            guard let deviceID else { return nil }
            do {
                try await spoofer.prepare(deviceID: deviceID)
                return .prepared
            } catch {
                return .preparationFailed(Self.message(error))
            }

        case .prepared:
            // Auto start point: set the device to the Mac's current location.
            guard let deviceID = state.selectedDeviceID, let mac = await MacLocation.current() else { return nil }
            try? await spoofer.setLocation(deviceID: deviceID, to: mac)
            return .startPointResolved(mac)

        case let .setLocation(coordinate):
            guard let deviceID = state.selectedDeviceID else { return nil }
            do {
                try await spoofer.setLocation(deviceID: deviceID, to: coordinate)
                return .locationSet(coordinate)
            } catch {
                return .failed(Self.message(error))
            }

        case .startNavigation:
            guard let deviceID = state.selectedDeviceID, let start = state.spoofedLocation,
                  !state.waypoints.isEmpty else { return nil }
            do {
                let route = try await Self.route(through: [start] + state.waypoints, speed: state.speed)
                try await spoofer.navigate(deviceID: deviceID, route: route, speed: state.speed)
                return .navigationStarted(RoutePath(points: route))
            } catch {
                return .failed(Self.message(error))
            }

        case .reset:
            guard let deviceID = state.selectedDeviceID else { return nil }
            try? await spoofer.reset(deviceID: deviceID)
            return .didReset

        default:
            return nil
        }
    }

    // MARK: - Routing

    /// Compute a route through an ordered list of stops (start + waypoints), concatenating
    /// the per-leg directions polylines. Falls back to a straight line for any leg with no
    /// route (e.g. over water).
    private static func route(through stops: [Coordinate], speed: MovementSpeed) async throws -> [Coordinate] {
        guard stops.count >= 2 else { return stops }
        var result: [Coordinate] = []
        for index in 1 ..< stops.count {
            let leg = await Self.leg(from: stops[index - 1], to: stops[index], speed: speed)
            if index == 1 { result.append(contentsOf: leg) } else { result.append(contentsOf: leg.dropFirst()) }
        }
        return result
    }

    private static func leg(from start: Coordinate, to end: Coordinate, speed: MovementSpeed) async -> [Coordinate] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.clCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.clCoordinate))
        request.transportType = speed == .drive ? .automobile : .walking

        guard let response = try? await MKDirections(request: request).calculate(),
              let polyline = response.routes.first?.polyline
        else {
            return [start, end]
        }
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount
        )
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords.map { Coordinate($0) }
    }

    private static func message(_ error: Error) -> String {
        if let spooferError = error as? SpooferError {
            switch spooferError {
            case .backendUnavailable: return "go-ios backend not found."
            case let .tunnelFailed(reason): return "Tunnel failed: \(reason)"
            case let .locationFailed(reason): return "Location failed: \(reason)"
            case let .developerImageFailed(reason): return "Developer image failed: \(reason)"
            }
        }
        return "\(error)"
    }
}
