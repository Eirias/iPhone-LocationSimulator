//
//  AppReducer.swift
//  AppStore
//

import Models
import Redux

public typealias AppStore = Store<AppState, AppEvent>

public struct AppReducer: Reducer {
    public init() {}

    public func reduce(_ state: inout AppState, _ action: AppEvent) {
        switch action {
        case .onAppear, .refreshDevices:
            break

        case let .devicesLoaded(devices):
            state.devices = devices
            state.backendAvailable = true
            // Drop selection if the device disappeared.
            if let id = state.selectedDeviceID, !devices.contains(where: { $0.id == id }) {
                state.selectedDeviceID = nil
                state.isPrepared = false
                state.spoofedLocation = nil
            }

        case .backendUnavailable:
            state.backendAvailable = false

        case let .selectDevice(id):
            state.selectedDeviceID = id
            state.isPrepared = false
            state.isPreparing = id != nil
            state.spoofedLocation = nil
            state.waypoints = []
            state.route = nil
            state.travelledDistance = 0
            state.isNavigating = false

        case .prepared:
            state.isPreparing = false
            state.isPrepared = true

        case let .preparationFailed(message):
            state.isPreparing = false
            state.isPrepared = false
            state.errorMessage = message

        case let .startPointResolved(coordinate):
            // Auto start point (Mac location) — only if the user hasn't set one yet.
            if state.spoofedLocation == nil { state.spoofedLocation = coordinate }

        case let .mapClicked(coordinate):
            if state.spoofedLocation == nil {
                // First click sets the start point (teleport).
                state.spoofedLocation = coordinate
            } else {
                // Subsequent clicks add navigation waypoints.
                state.waypoints.append(coordinate)
            }

        case let .setLocation(coordinate):
            state.isNavigating = false
            state.route = nil
            state.spoofedLocation = coordinate

        case let .locationSet(coordinate):
            state.spoofedLocation = coordinate

        case let .addWaypoint(coordinate):
            state.waypoints.append(coordinate)

        case .clearWaypoints:
            state.waypoints = []
            state.route = nil

        case let .setSpeed(speed):
            state.speed = speed

        case .startNavigation:
            break // side-effect only (route computed in middleware)

        case let .navigationStarted(route):
            state.route = route
            state.travelledDistance = 0
            state.isNavigating = !route.isEmpty

        case let .navigationTick(deltaTime):
            guard state.isNavigating, let route = state.route else { break }
            state.travelledDistance += state.speed.metersPerSecond * deltaTime
            state.spoofedLocation = route.point(atDistance: state.travelledDistance)
            if state.travelledDistance >= route.totalDistance {
                state.travelledDistance = route.totalDistance
                state.isNavigating = false
                state.waypoints = []
            }

        case .navigationFinished:
            state.isNavigating = false

        case .reset:
            state.isNavigating = false
            state.waypoints = []
            state.route = nil
            state.travelledDistance = 0

        case .didReset:
            state.spoofedLocation = nil
            state.isNavigating = false
            state.waypoints = []
            state.route = nil
            state.travelledDistance = 0

        case let .failed(message):
            state.errorMessage = message
            state.isNavigating = false

        case .dismissError:
            state.errorMessage = nil
        }
    }
}
