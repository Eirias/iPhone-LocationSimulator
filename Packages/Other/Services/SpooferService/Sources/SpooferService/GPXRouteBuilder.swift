//
//  GPXRouteBuilder.swift
//  SpooferService
//
//  Turns a route (ordered coordinates from MapKit directions) + a speed into a timed GPX
//  track. go-ios `setlocationgpx` replays the track honouring the per-point timestamps,
//  so spacing points by `speed × dt` reproduces the chosen movement speed.
//

import Foundation
import Models

enum GPXRouteBuilder {
    /// Resample `route` so consecutive points are ~`speed × dt` metres apart, then emit a
    /// GPX where each point is `dt` seconds after the previous. A hard cap on point count
    /// keeps very long routes from producing huge files (dt is scaled up if needed).
    static func makeGPX(route: [Coordinate], speed: MovementSpeed, maxPoints: Int = 8000) -> String {
        guard route.count >= 2 else {
            return gpxDocument(points: route.map { ($0, 0.0) })
        }

        let (resampled, dt) = resampledRoute(route: route, speed: speed, maxPoints: maxPoints)
        var timed: [(Coordinate, Double)] = []
        for (index, coordinate) in resampled.enumerated() {
            timed.append((coordinate, Double(index) * dt))
        }
        return gpxDocument(points: timed)
    }

    /// Resample `route` into points ~`speed × dt` metres apart, returning the points and the
    /// per-point time interval. Shared by ``makeGPX`` and by navigation stepping, which
    /// drives `setlocation` point-by-point (the proven teleport path) instead of relying on
    /// `setlocationgpx` GPX playback.
    static func resampledRoute(
        route: [Coordinate],
        speed: MovementSpeed,
        maxPoints: Int = 8000
    ) -> (points: [Coordinate], dt: Double) {
        guard route.count >= 2 else { return (route, 1.0) }
        let totalDistance = routeDistance(route)
        var dt = 1.0
        // Step distance per dt seconds.
        var step = max(speed.metersPerSecond * dt, 1.0)
        // If too many points would result, stretch dt (fewer, coarser points).
        if totalDistance / step > Double(maxPoints) {
            step = totalDistance / Double(maxPoints)
            dt = step / speed.metersPerSecond
        }
        return (resample(route: route, step: step), dt)
    }

    // MARK: - Geometry

    private static func routeDistance(_ route: [Coordinate]) -> Double {
        var total = 0.0
        for index in 1 ..< route.count {
            total += haversine(route[index - 1], route[index])
        }
        return total
    }

    /// Walk the polyline and emit a point every `step` metres.
    private static func resample(route: [Coordinate], step: Double) -> [Coordinate] {
        var result: [Coordinate] = [route[0]]
        var carry = 0.0
        for index in 1 ..< route.count {
            let start = route[index - 1]
            let end = route[index]
            let segment = haversine(start, end)
            guard segment > 0 else { continue }
            var distanceAlong = step - carry
            while distanceAlong <= segment {
                let fraction = distanceAlong / segment
                result.append(interpolate(start, end, fraction))
                distanceAlong += step
            }
            carry = (segment - (distanceAlong - step))
        }
        if result.last != route.last { result.append(route.last!) }
        return result
    }

    private static func interpolate(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Great-circle distance in metres.
    private static func haversine(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - GPX document

    private static func gpxDocument(points: [(Coordinate, Double)]) -> String {
        // Fixed base time keeps output deterministic; only the deltas matter for replay.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var trkpts = ""
        for (coordinate, offset) in points {
            let time = formatter.string(from: base.addingTimeInterval(offset))
            trkpts += """
                <trkpt lat="\(coordinate.latitude)" lon="\(coordinate.longitude)"><time>\(time)</time></trkpt>

            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LocationSimulator">
          <trk><trkseg>
        \(trkpts)  </trkseg></trk>
        </gpx>
        """
    }
}
