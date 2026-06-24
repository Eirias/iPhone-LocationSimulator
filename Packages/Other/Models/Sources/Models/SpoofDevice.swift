//
//  SpoofDevice.swift
//  Models
//
//  A connected real iOS device that can be spoofed.
//

import Foundation

public struct SpoofDevice: Sendable, Identifiable, Hashable {
    public enum ConnectionType: String, Sendable, Codable {
        case usb, network, unknown
    }

    /// UDID — stable unique id.
    public let id: String
    public let name: String
    /// OS version string, e.g. "26.5".
    public let version: String?
    /// Model identifier, e.g. "iPhone17,1".
    public let productType: String?
    public let connectionType: ConnectionType

    public init(
        id: String,
        name: String,
        version: String?,
        productType: String?,
        connectionType: ConnectionType
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.productType = productType
        self.connectionType = connectionType
    }
}
