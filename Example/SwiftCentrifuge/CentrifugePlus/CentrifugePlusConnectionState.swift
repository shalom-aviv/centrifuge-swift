//
//  CentrifugePlusConnectionState.swift
//  SwiftCentrifuge
//

import Foundation

enum CentrifugePlusConnectionState {
    case common(CommonState)
    case pause(PauseState)

    enum CommonState: Equatable {
        case alive
        case disconnect
    }

    enum PauseState: Equatable {
        case disconnectCalled
        case awaitRestoreEvent
        case autoRestore
    }
}

extension CentrifugePlusConnectionState {
    var isPermanentConnecting: Bool {
        guard let pauseState else { return false }
        switch pauseState {
        case .disconnectCalled: return false
        case .awaitRestoreEvent: return true
        case .autoRestore: return true
        }
    }

    var pauseState: PauseState? {
        switch self {
        case let .pause(state): return state
        case .common: return nil
        }
    }
}
