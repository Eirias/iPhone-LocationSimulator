//
//  SpooferClientMock.swift
//  SpooferService
//
//  In-memory SpooferClient for SwiftUI previews and tests. No device required.
//

import Foundation
import Models
import SpooferInterface

public struct SpooferClientMock: SpooferClient {
    public var devices: [SpoofDevice]

    public init(devices: [SpoofDevice] = SpooferClientMock.sampleDevices) {
        self.devices = devices
    }

    public static let sampleDevices: [SpoofDevice] = [
        SpoofDevice(id: "MOCK-UDID-0001", name: "Mock iPhone", version: "26.5",
                    productType: "iPhone17,1", connectionType: .usb),
    ]

    public func connectedDevices() async throws -> [SpoofDevice] {
        devices
    }

    public func prepare(deviceID _: String) async throws {}
    public func setLocation(deviceID _: String, to _: Coordinate) async throws {}
    public func navigate(deviceID _: String, route _: [Coordinate], speed _: MovementSpeed) async throws {}
    public func reset(deviceID _: String) async throws {}
    public func shutdown(deviceID _: String) async {}
}
