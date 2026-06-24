//
//  SidebarView.swift
//  SidebarFeature
//
//  Device list. Selecting a device prepares it (tunnel + DDI) via the store.
//

import AppStore
import DesignSystem
import Localization
import Models
import SwiftUI

public struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTheme) private var theme

    public init() {}

    public var body: some View {
        @Bindable var store = store
        List(selection: Binding(
            get: { store.selectedDeviceID },
            set: { store.send(.selectDevice($0)) }
        )) {
            Section(L10n.devicesHeader.value) {
                ForEach(store.devices) { device in
                    DeviceRow(device: device, isPreparing: store.isPreparing && store.selectedDeviceID == device.id)
                        .tag(device.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(L10n.appName.value)
        .task { store.send(.onAppear) }
    }
}

private struct DeviceRow: View {
    let device: SpoofDevice
    let isPreparing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.connectionType == .network ? "wifi" : "cable.connector")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body)
                if let version = device.version {
                    Text("iOS \(version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isPreparing { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 2)
    }
}
