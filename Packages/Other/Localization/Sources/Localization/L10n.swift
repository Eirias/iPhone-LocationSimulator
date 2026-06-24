//
//  L10n.swift
//  Localization
//
//  Single source of truth for user-facing strings. Add a key here + a row in
//  Resources/Localizable.xcstrings. English is primary; a new language = add its column
//  in the catalog. `localeOverride` lets the app switch language at runtime from one place.
//

import Foundation

public enum L10n: String, CaseIterable, Sendable {
    case appName = "app_name"
    case devicesHeader = "devices_header"
    case noDeviceTitle = "no_device_title"
    case noDeviceSubtitle = "no_device_subtitle"
    case searchPlaceholder = "search_placeholder"
    case preparing
    case setLocationHere = "set_location_here"
    case navigateHere = "navigate_here"
    case stop
    case reset
    case speedWalk = "speed_walk"
    case speedCycle = "speed_cycle"
    case speedDrive = "speed_drive"
    case backendMissingTitle = "backend_missing_title"
    case backendMissingMessage = "backend_missing_message"

    /// Localized value for the current (or overridden) locale.
    public var value: String {
        L10n.bundle.localizedString(forKey: rawValue, value: rawValue, table: nil)
    }

    /// Set to a language code (e.g. "de") to override the system language app-wide.
    public nonisolated(unsafe) static var localeOverride: String?

    private static var bundle: Bundle {
        if let code = localeOverride,
           let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let localeBundle = Bundle(path: path)
        {
            return localeBundle
        }
        return .module
    }
}
