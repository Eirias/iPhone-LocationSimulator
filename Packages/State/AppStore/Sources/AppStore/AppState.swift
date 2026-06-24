//
//  AppState.swift
//  AppStore
//

import Foundation
import Models

public struct AppState: Sendable, Equatable {
    public var devices: [SpoofDevice] = []
    public var selectedDeviceID: String?
    public var backendAvailable = true

    /// Tunnel/DDI preparation in progress for the selected device.
    public var isPreparing = false
    /// Whether the selected device is prepared (tunnel up, DDI mounted).
    public var isPrepared = false

    /// The currently spoofed location (the held marker / animated position), if any.
    public var spoofedLocation: Coordinate?
    /// Ordered navigation waypoints the user added by clicking the map.
    public var waypoints: [Coordinate] = []
    public var speed: MovementSpeed = .walk

    /// The computed route currently being navigated (start → waypoints).
    public var route: RoutePath?
    /// Distance (metres) travelled along `route` so far — drives the marker + the
    /// travelled/remaining split.
    public var travelledDistance: Double = 0
    public var isNavigating = false

    public var errorMessage: String?

    public init() {}

    public var selectedDevice: SpoofDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    /// True once we have a start point and at least one waypoint to navigate to.
    public var canNavigate: Bool {
        spoofedLocation != nil && !waypoints.isEmpty
    }
}
