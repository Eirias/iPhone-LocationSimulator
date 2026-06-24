//
//  LocationSearch.swift
//  MapFeature
//
//  Apple-Maps-style location search (ported from the original app's SuggestionPopup):
//  live autocomplete via MKLocalSearchCompleter, and resolution of a chosen suggestion to
//  a map region. Selecting a result zooms the map there — it does NOT teleport the device
//  (the user teleports by tapping the map, same as the original).
//

import Localization
import MapKit
import Observation
import SwiftUI

@MainActor
@Observable
final class LocationSearch: NSObject, MKLocalSearchCompleterDelegate {
    /// The text the user is typing; drives the completer.
    var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    /// Live autocomplete suggestions for `query`.
    private(set) var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    func clear() {
        query = ""
        suggestions = []
    }

    /// Resolve a chosen completion to a bounding region to zoom the map to.
    func resolveRegion(for completion: MKLocalSearchCompletion) async -> MKCoordinateRegion? {
        let response = try? await MKLocalSearch(request: .init(completion: completion)).start()
        return response?.boundingRegion
    }

    // MARK: MKLocalSearchCompleterDelegate (callbacks are delivered on the main thread)

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // MKLocalSearchCompletion isn't Sendable; the completer delivers on the main thread
        // and we only read these on the main actor, so hopping them over is safe.
        nonisolated(unsafe) let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_: MKLocalSearchCompleter, didFailWithError _: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

// MARK: - Search field

/// A floating search box with a results dropdown, overlaid on the map.
struct LocationSearchField: View {
    @Bindable var search: LocationSearch
    @Environment(\.appTheme) private var theme
    /// Called with the region to zoom to when the user picks a suggestion.
    var onPick: (MKCoordinateRegion) -> Void

    private let cornerRadius: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.searchPlaceholder.value, text: $search.query)
                    .textFieldStyle(.plain)
                if !search.query.isEmpty {
                    Button { search.clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)

            if !search.suggestions.isEmpty {
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(search.suggestions.enumerated()), id: \.element) { index, suggestion in
                            if index > 0 { Divider() }
                            suggestionRow(suggestion)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(radius: 6, y: 2)
    }

    private func suggestionRow(_ suggestion: MKLocalSearchCompletion) -> some View {
        Button { pick(suggestion) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .foregroundStyle(.primary)
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        Task {
            if let region = await search.resolveRegion(for: suggestion) {
                onPick(region)
            }
            search.clear()
        }
    }
}
