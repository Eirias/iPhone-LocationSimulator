//
//  Log.swift
//  Core
//
//  Tiny logging facade over os.Logger so feature packages don't each depend on os.log
//  directly and we can reroute later.
//

import Foundation
import os

public enum Log {
    private static let logger = Logger(subsystem: "com.eirias.locationsimulator", category: "app")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
