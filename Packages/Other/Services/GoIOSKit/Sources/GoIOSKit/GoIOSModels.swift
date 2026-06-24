//
//  GoIOSModels.swift
//  GoIOSKit
//
//  Value types and errors for the go-ios wrapper.
//

import Foundation

/// Connection transport reported by go-ios for a device.
public enum GoIOSConnectionType: String, Sendable {
    case usb
    case network
    case unknown
}

/// A running tunnel's connection endpoint (from `go-ios tunnel ls`). Passed explicitly to
/// location commands that don't auto-discover the tunnel reliably (notably setlocationgpx).
public struct GoIOSTunnelEndpoint: Sendable, Equatable {
    public let address: String
    public let rsdPort: Int

    public init(address: String, rsdPort: Int) {
        self.address = address
        self.rsdPort = rsdPort
    }

    public var arguments: [String] {
        ["--address=\(address)", "--rsd-port=\(rsdPort)"]
    }
}

/// Structured information about a connected iOS device, parsed from `go-ios info`.
public struct GoIOSDeviceInfo: Sendable, Equatable {
    /// Unique device ID (UDID).
    public let udid: String
    /// Human readable device name, e.g. "LoVo's iPhone".
    public let name: String
    /// OS version string, e.g. "26.5".
    public let version: String?
    /// Product name, e.g. "iPhone OS".
    public let productName: String?
    /// Product type / model identifier, e.g. "iPhone17,1".
    public let productType: String?
    /// Connection transport, when known.
    public let connectionType: GoIOSConnectionType

    public init(
        udid: String,
        name: String,
        version: String?,
        productName: String?,
        productType: String?,
        connectionType: GoIOSConnectionType = .usb
    ) {
        self.udid = udid
        self.name = name
        self.version = version
        self.productName = productName
        self.productType = productType
        self.connectionType = connectionType
    }

    /// Major OS version, e.g. 26 for "26.5".
    public var majorVersion: Int? {
        guard let first = version?.split(separator: ".").first else { return nil }
        return Int(first)
    }
}

/// Errors thrown by ``GoIOS``.
public enum GoIOSError: Error, CustomStringConvertible {
    /// The go-ios binary could not be located on disk / in PATH.
    case binaryNotFound(searched: [String])
    /// The process could not be launched.
    case launchFailed(String)
    /// go-ios exited non-zero or emitted an ERROR log line. Carries the best error
    /// message extracted from the JSON-lines output plus the raw output for debugging.
    case commandFailed(message: String, raw: String, exitCode: Int32)
    /// The output could not be parsed into the expected shape.
    case unexpectedOutput(String)
    /// A required developer service was unreachable — almost always means the iOS 17+
    /// tunnel is not running. Detected from the `InvalidService` /
    /// `com.apple.dt.simulatelocation` signature in go-ios output.
    case tunnelNotRunning
    /// Our own tunnel child could not bind the tunnel-info port because another go-ios
    /// tunnel/agent already owns it. Riding that foreign tunnel is unsafe — it may be
    /// stale and silently fail to apply the location (the `tunnel ls` endpoint then points
    /// at a dead RSD address) — so we surface this instead of proceeding.
    case tunnelPortInUse(port: Int)

    public var description: String {
        switch self {
        case let .binaryNotFound(searched):
            return "go-ios binary not found. Searched: \(searched.joined(separator: ", "))"
        case let .launchFailed(reason):
            return "Failed to launch go-ios: \(reason)"
        case let .commandFailed(message, _, code):
            return "go-ios command failed (exit \(code)): \(message)"
        case let .unexpectedOutput(detail):
            return "Unexpected go-ios output: \(detail)"
        case .tunnelNotRunning:
            return "iOS 17+ tunnel is not running. Start it with 'sudo go-ios tunnel start'."
        case let .tunnelPortInUse(port):
            return "Another go-ios tunnel/agent already owns port \(port). Stop it "
                + "(e.g. `pkill -f 'go-ios.*tunnel start'`) and try again."
        }
    }
}

/// Raw result of a single go-ios invocation.
///
/// Only the raw output and exit code are stored (both `Sendable`); the parsed JSON
/// lines are derived on demand so the type stays `Sendable` under Swift 6 without
/// holding a non-`Sendable` `[[String: Any]]`.
public struct GoIOSInvocation: Sendable {
    /// Combined raw stdout+stderr, for diagnostics and parsing.
    public let raw: String
    /// Process exit code.
    public let exitCode: Int32

    public init(raw: String, exitCode: Int32) {
        self.raw = raw
        self.exitCode = exitCode
    }

    /// Every line of `raw` parsed as a JSON object (non-JSON lines dropped).
    public var jsonLines: [[String: Any]] {
        GoIOS.parseJSONLines(raw)
    }

    /// Log lines whose `level` is `ERROR`.
    public var errorLines: [[String: Any]] {
        jsonLines.filter { ($0["level"] as? String)?.uppercased() == "ERROR" }
    }
}
