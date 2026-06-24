//
//  MapFeatureView.swift
//  MapFeature
//
//  The map. First click sets the start (if no auto start point); further clicks add
//  navigation waypoints. "Navigate" routes start → waypoints at the chosen speed: go-ios
//  moves the device while the marker animates here, with the route drawn as travelled
//  (light blue) + remaining (dark blue).
//

import AppStore
import DesignSystem
import Localization
import MapKit
import Models
import SwiftUI

public struct MapFeatureView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    @State private var camera: MapCameraPosition = .automatic
    @State private var search = LocationSearch()
    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private let travelledColor = Color(red: 0.40, green: 0.72, blue: 1.0)
    private let remainingColor = Color(red: 0.0, green: 0.36, blue: 0.90)

    public init() {}

    public var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                routeContent
                waypointContent
                if let current = store.spoofedLocation {
                    Annotation("", coordinate: current.clCoordinate) {
                        Circle()
                            .fill(remainingColor)
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 16, height: 16)
                            .shadow(radius: 2)
                    }
                }
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                let model = Coordinate(coordinate)
                if store.spoofedLocation == nil {
                    store.send(.setLocation(model)) // first click = start
                } else if !store.isNavigating {
                    store.send(.addWaypoint(model)) // further clicks = waypoints
                }
            }
        }
        .overlay(alignment: .bottom) { controls }
        .overlay(alignment: .top) { topOverlay }
        .onReceive(ticker) { _ in
            if store.isNavigating { store.send(.navigationTick(0.2)) }
        }
        .onChange(of: store.spoofedLocation) { _, newValue in
            // Recenter on teleport / start; don't fight the user while navigating.
            guard let newValue, !store.isNavigating else { return }
            camera = .region(MKCoordinateRegion(
                center: newValue.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    @MapContentBuilder
    private var routeContent: some MapContent {
        if let route = store.route {
            let parts = route.split(atDistance: store.travelledDistance)
            MapPolyline(coordinates: parts.travelled.map(\.clCoordinate))
                .stroke(travelledColor, lineWidth: 6)
            MapPolyline(coordinates: parts.remaining.map(\.clCoordinate))
                .stroke(remainingColor, lineWidth: 6)
        } else if let start = store.spoofedLocation, !store.waypoints.isEmpty {
            // Preview before navigation: straight hint line through the stops.
            MapPolyline(coordinates: ([start] + store.waypoints).map(\.clCoordinate))
                .stroke(remainingColor.opacity(0.4), lineWidth: 3)
        }
    }

    @MapContentBuilder
    private var waypointContent: some MapContent {
        ForEach(Array(store.waypoints.enumerated()), id: \.offset) { index, waypoint in
            Marker("\(index + 1)", systemImage: "mappin", coordinate: waypoint.clCoordinate)
                .tint(theme.palette.pin)
        }
    }

    private var topOverlay: some View {
        VStack(spacing: theme.spacing.s) {
            LocationSearchField(search: search) { region in
                camera = .region(region)
            }
            preparingBanner
        }
        .padding(theme.spacing.m)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var preparingBanner: some View {
        if store.isPreparing {
            Label(L10n.preparing.value, systemImage: "bolt.horizontal.circle")
                .padding(.horizontal, theme.spacing.m)
                .padding(.vertical, theme.spacing.s)
                .background(.thinMaterial, in: Capsule())
                .padding(theme.spacing.m)
        }
    }

    private var controls: some View {
        HStack(spacing: theme.spacing.m) {
            Picker("", selection: Binding(
                get: { store.speed },
                set: { store.send(.setSpeed($0)) }
            )) {
                Label(L10n.speedWalk.value, systemImage: MovementSpeed.walk.symbolName).tag(MovementSpeed.walk)
                Label(L10n.speedCycle.value, systemImage: MovementSpeed.cycle.symbolName).tag(MovementSpeed.cycle)
                Label(L10n.speedDrive.value, systemImage: MovementSpeed.drive.symbolName).tag(MovementSpeed.drive)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(store.isNavigating)

            Divider().frame(height: 20)

            if store.isNavigating {
                Button(L10n.stop.value) { store.send(.reset) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(L10n.navigateHere.value) { store.send(.startNavigation) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canNavigate)
            }

            Button(L10n.reset.value) { store.send(.reset) }
                .disabled(store.spoofedLocation == nil)
        }
        .padding(theme.spacing.m)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        .padding(theme.spacing.l)
    }
}
