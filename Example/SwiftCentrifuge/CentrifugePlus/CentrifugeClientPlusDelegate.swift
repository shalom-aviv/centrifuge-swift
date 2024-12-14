//
//  CentrifugeClientPlusDelegate.swift
//  SwiftCentrifuge
//

import Foundation
import SwiftCentrifuge

final class CentrifugeClientPlusDelegate {
    private var connectionState = CentrifugePlusConnectionState.common(.alive)
    private let syncQueue: DispatchQueue
    private weak var clientDelegate: CentrifugeClientDelegate?

    var delegate: CentrifugeClientDelegate? {
        set { syncQueue.sync { clientDelegate = newValue }  }
        get { syncQueue.sync { clientDelegate } }
    }

    init(syncQueue: DispatchQueue, delegate: CentrifugeClientDelegate? = nil) {
        self.syncQueue = syncQueue
        self.delegate = delegate
    }
}

extension CentrifugeClientPlusDelegate: CentrifugeClientDelegate {
    func onConnected(_ client: CentrifugeClient, _ event: CentrifugeConnectedEvent) {
        syncQueue.async { [weak clientDelegate] in
            clientDelegate?.onConnected(client, event)
        }
    }

    func onDisconnected(_ client: CentrifugeClient, _ event: CentrifugeDisconnectedEvent) {
        syncQueue.async { [weak self] in
            guard let self else { return }
            if self.connectionState.isPermanentConnecting {
                clientDelegate?.onConnecting(client, CentrifugeConnectingEvent())
//                switch self.connectionState {
//
//                }

            } else {
                clientDelegate?.onDisconnected(client, event)
            }
        }
    }

    func onConnecting(_ client: CentrifugeClient, _ event: CentrifugeConnectingEvent) {
        syncQueue.async { [weak clientDelegate] in
            clientDelegate?.onConnecting(client, event)
        }
    }

    func onError(_ client: CentrifugeClient, _ event: CentrifugeErrorEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onError(client, event) }
    }

    func onMessage(_ client: CentrifugeClient, _ event: CentrifugeMessageEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onMessage(client, event) }
    }

    func onSubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribedEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onSubscribed(client, event) }
    }

    func onUnsubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerUnsubscribedEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onUnsubscribed(client, event) }
    }

    func onSubscribing(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribingEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onSubscribing(client, event) }
    }

    func onPublication(_ client: CentrifugeClient, _ event: CentrifugeServerPublicationEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onPublication(client, event) }
    }

    func onJoin(_ client: CentrifugeClient, _ event: CentrifugeServerJoinEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onJoin(client, event) }
    }

    func onLeave(_ client: CentrifugeClient, _ event: CentrifugeServerLeaveEvent) {
        syncQueue.async { [weak clientDelegate] in clientDelegate?.onLeave(client, event) }
    }
}

