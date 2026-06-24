//
//  RoutePath.swift
//  Models
//
//  An ordered polyline with cumulative distances, so navigation can advance by metres and
//  the map can split it into a travelled and a remaining part.
//

import CoreLocation
import Foundation

public struct RoutePath: Sendable, Equatable {
    public let points: [Coordinate]
    /// Cumulative distance (metres) at each point; `cumulative[0] == 0`.
    public let cumulative: [Double]
    public var totalDistance: Double {
        cumulative.last ?? 0
    }

    public init(points: [Coordinate]) {
        self.points = points
        var sums: [Double] = []
        var total = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 { total += RoutePath.distance(points[index - 1], point) }
            sums.append(total)
        }
        cumulative = sums
    }

    public var isEmpty: Bool {
        points.count < 2
    }

    /// Point at a given travelled distance (metres) along the path.
    public func point(atDistance distance: Double) -> Coordinate {
        guard points.count >= 2 else { return points.first ?? Coordinate(latitude: 0, longitude: 0) }
        if distance <= 0 { return points.first! }
        if distance >= totalDistance { return points.last! }
        // Find the segment containing `distance`.
        var index = 1
        while index < cumulative.count && cumulative[index] < distance {
            index += 1
        }
        let segStart = cumulative[index - 1]
        let segEnd = cumulative[index]
        let fraction = segEnd > segStart ? (distance - segStart) / (segEnd - segStart) : 0
        return RoutePath.interpolate(points[index - 1], points[index], fraction)
    }

    /// Split into (travelled, remaining) coordinate lists at a travelled distance.
    public func split(atDistance distance: Double) -> (travelled: [Coordinate], remaining: [Coordinate]) {
        guard points.count >= 2 else { return (points, points) }
        let clamped = min(max(distance, 0), totalDistance)
        let current = point(atDistance: clamped)
        var travelled: [Coordinate] = []
        var remaining: [Coordinate] = []
        for (index, point) in points.enumerated() {
            if cumulative[index] <= clamped { travelled.append(point) } else { remaining.append(point) }
        }
        travelled.append(current)
        remaining.insert(current, at: 0)
        return (travelled, remaining)
    }

    // MARK: - Geometry

    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func interpolate(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }
}
