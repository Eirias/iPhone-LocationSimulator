//
//  MacLocation.swift
//  AppStore
//
//  One-shot lookup of the Mac's own location (CoreLocation) used as the automatic start
//  point. Best-effort: returns nil if permission is denied or unavailable, in which case
//  the first map click sets the start instead.
//

import CoreLocation
import Foundation
import Models

enum MacLocation {
    static func current() async -> Coordinate? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Coordinate?, Never>) in
            DispatchQueue.main.async {
                let provider = MacLocationProvider()
                provider.request { continuation.resume(returning: $0) }
            }
        }
    }
}

private final class MacLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var completion: ((Coordinate?) -> Void)?
    private var retain: MacLocationProvider?

    func request(_ completion: @escaping (Coordinate?) -> Void) {
        self.completion = completion
        retain = self
        manager.delegate = self
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(nil)
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ coordinate: Coordinate?) {
        completion?(coordinate)
        completion = nil
        retain = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: finish(nil)
        case .notDetermined: break
        default: manager.requestLocation()
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.first.map { Coordinate($0.coordinate) })
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        finish(nil)
    }
}
