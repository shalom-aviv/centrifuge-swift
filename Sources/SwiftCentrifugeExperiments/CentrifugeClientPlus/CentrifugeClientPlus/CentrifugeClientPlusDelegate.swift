//
//  CentrifugeClientPlusDelegate.swift
//  SwiftCentrifuge
//

import Foundation
import SwiftCentrifuge

final class CentrifugeClientPlusDelegate {
    private let connection: CentrifugePlusConnection
    private let syncQueue: DispatchQueue
    private let delegateQueue: DispatchQueue
    private weak var clientDelegate: CentrifugeClientDelegate?

    var delegate: CentrifugeClientDelegate? {
        set { syncQueue.sync { clientDelegate = newValue }  }
        get { syncQueue.sync { clientDelegate } }
    }

    init(connection: CentrifugePlusConnection, syncQueue: DispatchQueue, delegate: CentrifugeClientDelegate? = nil, delegateQueue: DispatchQueue) {
        self.connection = connection
        self.syncQueue = syncQueue
        self.clientDelegate = delegate
        self.delegateQueue = delegateQueue
    }
}

extension CentrifugeClientPlusDelegate {
    func processDisconnectInPauseState(_ client: CentrifugeClient) {
        syncQueue.async { [weak self] in
            self?.connection.makeDisconnected()
            self?.delegateQueue.async {
                self?.clientDelegate?.onDisconnected(client, .disconnectCalled)
            }
        }
    }
}

extension CentrifugeClientPlusDelegate: CentrifugeClientDelegate {
    func onConnected(_ client: CentrifugeClient, _ event: CentrifugeConnectedEvent) {
        delegateQueue.async { [weak clientDelegate] in
            clientDelegate?.onConnected(client, event)
        }
    }

    func onDisconnected(_ client: CentrifugeClient, _ event: CentrifugeDisconnectedEvent) {
        syncQueue.async { [weak self] in
            guard let self else { return }

            if let pauseState = self.connection.pauseState {
                switch pauseState {
                case .autoRestore:
                    delegateQueue.async { [weak clientDelegate] in
                        clientDelegate?.onConnecting( client, .connectCalled)
                    }
                    self.connection.makeAlive()
                    client.connect()
                case .awaitRestoreEvent:
                    delegateQueue.async { [weak clientDelegate] in
                        clientDelegate?.onConnecting( client, .connectCalled)
                    }
                    break
                case .disconnectCalled:
                    self.connection.makeDisconnected()
                    delegateQueue.async { [weak clientDelegate] in clientDelegate?.onDisconnected(client, event) }
                }
            } else {
                self.connection.makeDisconnected()
                delegateQueue.async { [weak clientDelegate] in clientDelegate?.onDisconnected(client, event) }
            }
        }
    }

    func onConnecting(_ client: CentrifugeClient, _ event: CentrifugeConnectingEvent) {
        delegateQueue.async { [weak clientDelegate] in
            clientDelegate?.onConnecting(client, event)
        }
    }

    func onError(_ client: CentrifugeClient, _ event: CentrifugeErrorEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onError(client, event) }
    }

    func onMessage(_ client: CentrifugeClient, _ event: CentrifugeMessageEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onMessage(client, event) }
    }

    func onSubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribedEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onSubscribed(client, event) }
    }

    func onUnsubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerUnsubscribedEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onUnsubscribed(client, event) }
    }

    func onSubscribing(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribingEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onSubscribing(client, event) }
    }

    func onPublication(_ client: CentrifugeClient, _ event: CentrifugeServerPublicationEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onPublication(client, event) }
    }

    func onJoin(_ client: CentrifugeClient, _ event: CentrifugeServerJoinEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onJoin(client, event) }
    }

    func onLeave(_ client: CentrifugeClient, _ event: CentrifugeServerLeaveEvent) {
        delegateQueue.async { [weak clientDelegate] in clientDelegate?.onLeave(client, event) }
    }
}

