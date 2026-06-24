//
//  RootView.swift
//  LocationSimulator
//
//  Sidebar (devices) + detail (map). Handles the empty / backend-missing states.
//

import AppStore
import Localization
import MapFeature
import SidebarFeature
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 220)
        } detail: {
            detail
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.dismissError) } }
            ),
            presenting: store.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { store.send(.dismissError) }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !store.backendAvailable {
            ContentUnavailableView {
                Label(L10n.backendMissingTitle.value, systemImage: "terminal")
            } description: {
                Text(L10n.backendMissingMessage.value)
            }
        } else if store.selectedDevice == nil {
            ContentUnavailableView {
                Label(L10n.noDeviceTitle.value, systemImage: "iphone.slash")
            } description: {
                Text(L10n.noDeviceSubtitle.value)
            }
        } else {
            MapFeatureView()
        }
    }
}
