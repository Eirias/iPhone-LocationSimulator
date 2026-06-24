//
//  Coordinate.swift
//  Models
//
//  Framework-light geographic coordinate. Converts to/from CLLocationCoordinate2D at the
//  edges (map / CoreLocation), so domain + state stay Sendable/Equatable/Codable.
//

import CoreLocation
import Foundation

public struct Coordinate: Sendable, Codable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ clCoordinate: CLLocationCoordinate2D) {
        latitude = clCoordinate.latitude
        longitude = clCoordinate.longitude
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
