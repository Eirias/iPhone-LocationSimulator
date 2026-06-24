//
//  SpooferClient.swift
//  SpooferInterface
//
//  Contract for the location-spoofing backend. The live implementation
//  (SpooferService) drives go-ios; a mock is used for previews/tests. Features depend on
//  this protocol, never on go-ios directly.
//

import Foundation
import Models

public enum SpooferError: Error, Sendable, Equatable {
    /// The go-ios backend binary could not be located.
    case backendUnavailable
    /// The iOS 17+ tunnel could not be established.
    case tunnelFailed(String)
    /// Setting / navigating the location failed.
    case locationFailed(String)
    /// A developer-image mount step failed.
    case developerImageFailed(String)
}

public protocol SpooferClient: Sendable {
    /// Currently connected real devices (one poll).
    func connectedDevices() async throws -> [SpoofDevice]

    /// Bring up the (root-free, userspace) tunnel and mount the developer image for the
    /// device. Idempotent; blocks until ready.
    func prepare(deviceID: String) async throws

    /// Teleport: set and hold a single location.
    func setLocation(deviceID: String, to coordinate: Coordinate) async throws

    /// Navigate the spoofed location along `route` at `speed` (played as a timed GPX
    /// track over one connection).
    func navigate(deviceID: String, route: [Coordinate], speed: MovementSpeed) async throws

    /// Stop spoofing; the device reverts to its real GPS.
    func reset(deviceID: String) async throws

    /// Tear down the tunnel + any session for the device.
    func shutdown(deviceID: String) async
}
