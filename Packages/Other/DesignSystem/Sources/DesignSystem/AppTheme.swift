//
//  AppTheme.swift
//  DesignSystem
//
//  The single place to change the app's look: colours, spacing, radii, fonts. Injected
//  via the SwiftUI environment (`\.appTheme`). Default uses the system SF font.
//

import SwiftUI

public struct AppTheme: Sendable {
    public struct Spacing: Sendable {
        public let xs: CGFloat = 4
        public let s: CGFloat = 8
        public let m: CGFloat = 12
        public let l: CGFloat = 16
        public let xl: CGFloat = 24
    }

    public struct Palette: Sendable {
        public var accent: Color = .accentColor
        public var pin: Color = .red
        public var route: Color = .blue
        public var surface: Color = .init(nsColor: .windowBackgroundColor)
        public var secondaryText: Color = .secondary
    }

    public var palette = Palette()
    public let spacing = Spacing()
    public var cornerRadius: CGFloat = 10

    public init() {}

    // MARK: - Fonts (system SF)

    public func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default).weight(weight)
    }

    public var titleFont: Font {
        font(.title3, weight: .semibold)
    }

    public var bodyFont: Font {
        font(.body)
    }

    public var captionFont: Font {
        font(.caption)
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

public extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
