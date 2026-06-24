//
//  Redux.swift
//  Core
//
//  Minimal unidirectional-data-flow core: a Store that reduces actions into state and
//  runs async side effects via middleware. State and Action are app-defined.
//

import Foundation
import Observation

/// Pure state transition: applies an action to the state in place.
public protocol Reducer<State, Action> {
    associatedtype State
    associatedtype Action
    func reduce(_ state: inout State, _ action: Action)
}

/// Async side effect. Receives a snapshot of the post-reduce state and the action;
/// may emit a follow-up action which is fed back into the store.
public protocol Middleware<State, Action>: Sendable {
    associatedtype State: Sendable
    associatedtype Action: Sendable
    func process(state: State, action: Action) async -> Action?
}

/// Observable, main-actor store. Views read `state` (or via dynamic member lookup) and
/// dispatch with `send`.
@MainActor
@Observable
@dynamicMemberLookup
public final class Store<State: Sendable, Action: Sendable> {
    public private(set) var state: State

    private let reducer: any Reducer<State, Action>
    private let middlewares: [any Middleware<State, Action>]

    public init(
        initialState: State,
        reducer: any Reducer<State, Action>,
        middlewares: [any Middleware<State, Action>] = []
    ) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
    }

    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    /// Reduce synchronously, then fan out to middleware. Follow-up actions are dispatched
    /// back on the main actor.
    public func send(_ action: Action) {
        reducer.reduce(&state, action)
        let snapshot = state
        for middleware in middlewares {
            Task { [snapshot] in
                if let next = await middleware.process(state: snapshot, action: action) {
                    self.send(next)
                }
            }
        }
    }
}
