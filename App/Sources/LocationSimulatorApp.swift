//
//  LocationSimulatorApp.swift
//  LocationSimulator
//
//  App entry point: builds the Redux store with the live go-ios backend and injects it
//  plus the design theme into the environment.
//

import AppStore
import DesignSystem
import SpooferService
import SwiftUI

@main
struct LocationSimulatorApp: App {
    @State private var store: AppStore

    init() {
        let spoofer = SpooferServiceLive()
        _store = State(initialValue: AppStore(
            initialState: AppState(),
            reducer: AppReducer(),
            middlewares: [AppMiddleware(spoofer: spoofer)]
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.appTheme, AppTheme())
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
