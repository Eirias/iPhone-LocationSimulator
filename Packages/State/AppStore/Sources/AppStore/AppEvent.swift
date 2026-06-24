//
//  AppEvent.swift
//  AppStore
//

import Foundation
import Models

public enum AppEvent: Sendable, Equatable {
    // Lifecycle / discovery
    case onAppear
    case refreshDevices
    case devicesLoaded([SpoofDevice])
    case backendUnavailable

    // Selection / preparation
    case selectDevice(String?)
    case prepared
    case preparationFailed(String)
    /// Auto start point — the Mac's current location, set after preparation.
    case startPointResolved(Coordinate)

    // Spoofing
    case mapClicked(Coordinate) // first click = set start (teleport), else add waypoint
    case setLocation(Coordinate) // explicit teleport
    case locationSet(Coordinate)
    case addWaypoint(Coordinate)
    case clearWaypoints
    case setSpeed(MovementSpeed)

    // Navigation
    case startNavigation
    case navigationStarted(RoutePath)
    case navigationTick(Double) // advance by dt seconds
    case navigationFinished
    case reset
    case didReset

    // Errors
    case failed(String)
    case dismissError
}
