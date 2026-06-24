//
//  MovementSpeed.swift
//  Models
//
//  Speed presets for navigating the spoofed location toward a target.
//

import Foundation

public enum MovementSpeed: String, Sendable, CaseIterable, Identifiable, Codable {
    case walk
    case cycle
    case drive

    public var id: String {
        rawValue
    }

    /// Speed in metres per second, used to time the points of a navigation route.
    public var metersPerSecond: Double {
        switch self {
        case .walk: return 1.4 // ~5 km/h
        case .cycle: return 5.5 // ~20 km/h
        case .drive: return 13.9 // ~50 km/h
        }
    }

    /// SF Symbol used in the speed control.
    public var symbolName: String {
        switch self {
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        }
    }
}
