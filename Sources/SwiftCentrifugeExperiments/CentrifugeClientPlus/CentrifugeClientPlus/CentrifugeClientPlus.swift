//
//  CentrifugeClientPlus.swift
//  SwiftCentrifuge
//

import UIKit
import SwiftCentrifuge

public class CentrifugeClientPlus {
    fileprivate let syncQueue: DispatchQueue
    fileprivate let delegateQueue: DispatchQueue
    fileprivate let centrifugeClient: CentrifugeClient
    fileprivate let centrifugeClientPlusDelegate: CentrifugeClientPlusDelegate
    fileprivate let connection: CentrifugePlusConnection

    deinit {
        removeAppActivityObserving()
    }

    public init(endpoint: String, config: CentrifugeClientConfig, delegateQueue: DispatchQueue? = nil, delegate: CentrifugeClientDelegate? = nil) {
        let syncQueue = DispatchQueue(label: "com.centrifugal.centrifugeplus-swift.sync<\(UUID().uuidString)>")
        let delegateQueue = delegateQueue ?? DispatchQueue(label: "com.centrifugal.centrifugeplus-swift.delegate<\(UUID().uuidString)>")
        let connection = CentrifugePlusConnection()
        let centrifugeClientPlusDelegate = CentrifugeClientPlusDelegate(
            connection: connection,
            syncQueue: syncQueue,
            delegate: delegate,
            delegateQueue: delegateQueue
        )

        self.connection = connection
        self.syncQueue = syncQueue
        self.delegateQueue = delegateQueue
        self.centrifugeClientPlusDelegate = centrifugeClientPlusDelegate
        self.centrifugeClient = CentrifugeClient(
            endpoint: endpoint,
            config: config,
            delegate: centrifugeClientPlusDelegate
        )
    }
}

fileprivate extension CentrifugeClientPlus {
    func addAppActivityObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appActiveEvent),
            name: NSNotification.Name.UIApplicationWillResignActive,
//            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appInactiveEvent),
            name: NSNotification.Name.UIApplicationDidBecomeActive,
//            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func removeAppActivityObserving() {
        NotificationCenter.default.removeObserver(self)
    }
}

public extension CentrifugeClientPlus {
    weak var delegate: CentrifugeClientDelegate? {
        set { centrifugeClientPlusDelegate.delegate = newValue }
        get { centrifugeClientPlusDelegate.delegate }
    }

    var state: CentrifugeClientState { syncQueue.sync { centrifugeClient.state } }

    /**
     Connect to server.
     */
    func connect() {
        syncQueue.async { [weak self] in
            guard
                let self,
                self.connection.isReadyToConnect
            else {
                return
            }

            self.connection.makeAlive()
            self.centrifugeClient.connect()
        }
    }

    /**
     Disconnect from server.
     */
    func disconnect() {
        syncQueue.async { [weak self] in
            guard let self else { return }
            switch self.centrifugeClient.state {
            case .disconnected:
                centrifugeClientPlusDelegate.processDisconnectInPauseState(self.centrifugeClient)
            case .connected, .connecting:
                guard !self.connection.isAlreadyDisconnecting else {
                    return
                }
                self.connection.makeDisconnecting()
                self.centrifugeClient.disconnect()
            }
        }
    }

    /**
     Clears the reconnect state, resetting attempts and delays.
     Schedules a reconnect immediately if one was pending.
     */
    func resetReconnectState() {
        syncQueue.async { [weak self] in
            guard let self, self.connection.isAlive else {
                return
            }
            self.centrifugeClient.resetReconnectState()
        }
    }

    /**
     setToken allows updating connection token.
     - parameter token: String
     */
    func setToken(token: String) {
        centrifugeClient.setToken(token: token)
    }

    /**
     Create subscription object to specific channel with delegate
     - parameter channel: String
     - parameter delegate: CentrifugeSubscriptionDelegate
     - returns: CentrifugeSubscription
     */
    func newSubscription(channel: String, delegate: CentrifugeSubscriptionDelegate, config: CentrifugeSubscriptionConfig? = nil) throws -> CentrifugeSubscription {
        try centrifugeClient.newSubscription(
            channel: channel,
            delegate: delegate,
            config: config
        )
    }

    /**
     Try to get Subscription from internal client registry. Can return nil if Subscription
     does not exist yet.
     - parameter channel: String
     - returns: CentrifugeSubscription?
     */
    func getSubscription(channel: String) -> CentrifugeSubscription? {
        centrifugeClient.getSubscription(channel: channel)
    }

    /**
     * Say Client that Subscription should be removed from the internal registry. Subscription will be
     * automatically unsubscribed before removing.
     - parameter sub: CentrifugeSubscription
     */
    func removeSubscription(_ sub: CentrifugeSubscription) {
        centrifugeClient.removeSubscription(sub)
    }

    /**
     * Get a map with all client-side suscriptions in client's internal registry.
     */
    func getSubscriptions() -> [String: CentrifugeSubscription] {
        centrifugeClient.getSubscriptions()
    }

    /**
     Send raw asynchronous (without waiting for a response) message to server.
     - parameter data: Data
     - parameter completion: Completion block
     */
    func send(data: Data, completion: @escaping (Error?)->()) {
        centrifugeClient.send(
            data: data,
            completion: completion
        )
    }

    /**
     Publish message Data to channel.
     - parameter channel: String channel name
     - parameter data: Data message data
     - parameter completion: Completion block
     */
    func publish(channel: String, data: Data, completion: @escaping (Result<CentrifugePublishResult, Error>)->()) {
        centrifugeClient.publish(
            channel: channel,
            data: data,
            completion: completion
        )
    }

    /**
     Send RPC  command.
     - parameter method: String
     - parameter data: Data
     - parameter completion: Completion block
     */
    func rpc(method: String, data: Data, completion: @escaping (Result<CentrifugeRpcResult, Error>)->()) {
        centrifugeClient.rpc(
            method: method,
            data: data,
            completion: completion
        )
    }

    func presence(channel: String, completion: @escaping (Result<CentrifugePresenceResult, Error>)->()) {
        centrifugeClient.presence(
            channel: channel,
            completion: completion
        )
    }

    func presenceStats(channel: String, completion: @escaping (Result<CentrifugePresenceStatsResult, Error>)->()) {
        centrifugeClient.presenceStats(
            channel: channel,
            completion: completion
        )
    }

    func history(channel: String, limit: Int32 = 0, since: CentrifugeStreamPosition? = nil, reverse: Bool = false, completion: @escaping (Result<CentrifugeHistoryResult, Error>)->()) {
        centrifugeClient.history(
            channel: channel,
            limit: limit,
            since: since,
            reverse: reverse,
            completion: completion
        )
    }
}

private extension CentrifugeClientPlus {
    @objc func appActiveEvent() {
        syncQueue.async { [weak self] in
            guard let self, self.connection.isResumable else {
                return
            }
            if self.centrifugeClient.state == .disconnected {
                self.connection.makeAlive()
                self.centrifugeClient.connect()
            } else {
                self.connection.makeAutoResumable()
            }
        }
    }

    @objc func appInactiveEvent() {
        syncQueue.async { [weak self] in
            guard let self, self.connection.isAlive else {
                return
            }
            self.connection.makePause()
            self.centrifugeClient.disconnect()
        }
    }
}
