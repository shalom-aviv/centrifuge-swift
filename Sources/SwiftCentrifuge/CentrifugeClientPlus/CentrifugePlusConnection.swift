//
//  CentrifugePlusConnection.swift
//  SwiftCentrifuge
//

import Foundation

extension CentrifugePlusConnection {
    enum State {
        case common(CommonState)
        case pause(PauseState)
    }

    enum CommonState: Equatable {
        case disconnected
        case alive
        case disconnecting
    }

    enum PauseState: Equatable {
        case disconnectCalled
        case awaitRestoreEvent
        case autoRestore
    }
}

class CentrifugePlusConnection {
    fileprivate var connectionState = State.common(.alive)
    fileprivate var clientState = CentrifugeClientState.disconnected
}

extension CentrifugePlusConnection {
}

extension CentrifugePlusConnection {
    var state: State { connectionState }

    var isReadyToConnect: Bool {
        switch connectionState {
        case let .common(state):
            return state == .disconnected
        case .pause:
            return false
        }
    }

    func makeAlive() {
        connectionState = .common(.alive)
    }

    var isReadyToDisconnect: Bool {
        switch connectionState {
        case let .common(state):
            return state == .alive
        case .pause:
            return false
        }
    }

    var isAlreadyDisconnecting: Bool {
        switch connectionState {
        case let .common(state):
            return state == .disconnecting
        case let .pause(state):
            return state == .disconnectCalled
        }
    }
    func makeDisconnecting() {
        switch connectionState {
        case .common:
            connectionState = .common(.disconnecting)
        case .pause:
            connectionState = .pause(.disconnectCalled)
        }
    }

    func makeDisconnected() {
        connectionState = .common(.disconnected)
    }

    var isAlive: Bool {
        switch connectionState {
        case let .common(state):
            return state == .alive
        case .pause:
            return false
        }
    }

    func makePause(with autoRestore: Bool = false) {
        switch connectionState {
        case let .common(state):
            if state == .alive {
                connectionState = .pause(autoRestore ? .autoRestore : .awaitRestoreEvent)
            }
        case .pause:
            return
        }
    }

    var isResumable: Bool {
        switch connectionState {
        case .common:
            return false
        case let .pause(state):
            return state != .disconnectCalled
        }
    }

    var isAutoResumable: Bool {
        switch connectionState {
        case .common:
            return false
        case let .pause(state):
            return state == .autoRestore
        }
    }

    func makeAutoResumable() {
        connectionState = .pause(.autoRestore)
    }

    var pauseState: CentrifugePlusConnection.PauseState? {
        switch connectionState {
        case let .pause(state): return state
        case .common: return nil
        }
    }
}
