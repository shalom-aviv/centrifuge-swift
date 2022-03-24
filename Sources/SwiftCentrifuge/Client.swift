//
//  Client.swift
//  SwiftCentrifuge
//
//  Created by Alexander Emelin on 03/01/2019.
//  Copyright © 2019 Alexander Emelin. All rights reserved.
//

import Foundation
import SwiftProtobuf

public enum CentrifugeError: Error {
    case timeout
    case duplicateSub
    case clientFailed
    case clientDisconnected
    case subscriptionUnsubscribed
    case subscriptionFailed
    case transportError(error: Error)
    case connectError(error: Error)
    case refreshError(error: Error)
    case subscriptionSubscribeError(error: Error)
    case subscriptionRefreshError(error: Error)
    case replyError(code: UInt32, message: String)
}

public struct CentrifugeClientConfig {
    public var timeout = 5.0
    public var headers = [String:String]()
    public var tlsSkipVerify = false
    public var minReconnectDelay = 0.5
    public var maxReconnectDelay = 20.0
    public var maxServerPingDelay = 10.0
    public var privateChannelPrefix = "$"
    public var name = "swift"
    public var version = ""
    public var token: String?  = nil
    public var data: Data? = nil

    public init() {}
}

public enum CentrifugeClientState {
    case disconnected
    case connecting
    case connected
    case failed
}

public enum CentrifugeFailReason {
    case server
    case connectFailed
    case refreshFailed
    case unauthorized
    case unrecoverable
}

public class CentrifugeClient {
    public weak var delegate: CentrifugeClientDelegate?
    
    //MARK -
    fileprivate(set) var url: String
    fileprivate(set) var delegateQueue: OperationQueue
    fileprivate(set) var syncQueue: DispatchQueue
    fileprivate(set) var config: CentrifugeClientConfig
    
    //MARK -
    fileprivate(set) var state: CentrifugeClientState = .disconnected
    fileprivate var conn: WebSocket?
    fileprivate var token: String?
    fileprivate var data: Data?
    fileprivate var client: String?
    fileprivate var commandId: UInt32 = 0
    fileprivate var commandIdLock: NSLock = NSLock()
    fileprivate var opCallbacks: [UInt32: ((CentrifugeResolveData) -> ())] = [:]
    fileprivate var connectCallbacks: [String: ((Error?) -> ())] = [:]
    fileprivate var subscriptionsLock = NSLock()
    fileprivate var subscriptions = [CentrifugeSubscription]()
    fileprivate var serverSubs = [String: serverSubscription]()
    fileprivate var needReconnect = true
    fileprivate var numReconnectAttempts = 0
    fileprivate var pingTimer: DispatchSourceTimer?
    fileprivate var disconnectOpts: CentrifugeDisconnectOptions?
    fileprivate var refreshTask: DispatchWorkItem?
    fileprivate var connecting = false

    /// Initialize client.
    ///
    /// - Parameters:
    ///   - url: protobuf URL endpoint of Centrifugo/Centrifuge.
    ///   - config: config object.
    ///   - delegate: delegate protocol implementation to react on client events.
    ///   - delegateQueue: optional custom OperationQueue to execute client event callbacks.
    public init(url: String, config: CentrifugeClientConfig, delegate: CentrifugeClientDelegate? = nil, delegateQueue: OperationQueue? = nil) {
        self.url = url
        self.config = config
        self.delegate = delegate

        if config.token != nil {
            self.token = config.token;
        }
        if config.data != nil {
            self.data = config.data;
        }
        
        let queueID = UUID().uuidString
        self.syncQueue = DispatchQueue(label: "com.centrifugal.centrifuge-swift.sync<\(queueID)>")
        
        if let _queue = delegateQueue {
            self.delegateQueue = _queue
        } else {
            self.delegateQueue = OperationQueue()
            self.delegateQueue.maxConcurrentOperationCount = 1
        }
    }

    public func getState() -> CentrifugeClientState {
        var value: CentrifugeClientState!
        self.syncQueue.sync { [weak self] in
            guard let strongSelf = self else { return }
            value = strongSelf.state
        }
        return value
    }

    /**
     Connect to server.
     */
    public func connect() {
        self.syncQueue.async{ [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.connecting == false else { return }
            strongSelf.connecting = true
            strongSelf.needReconnect = true
            var request = URLRequest(url: URL(string: strongSelf.url)!)
            for (key, value) in strongSelf.config.headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
            let ws = WebSocket(request: request, protocols: ["centrifuge-protobuf"])
            if strongSelf.config.tlsSkipVerify {
                ws.disableSSLCertValidation = true
            }
            ws.onConnect = { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.onOpen()
            }
            ws.onDisconnect = { [weak self] (error: Error?) in
                guard let strongSelf = self else { return }
                var serverDisconnect: CentrifugeDisconnectOptions?

                // We act according to Disconnect code semantics.
                // See https://github.com/centrifugal/centrifuge/blob/master/disconnect.go.
                if let err = error as? WSError {
                    var code = err.code
                    let reconnect = code < 3500 || code >= 5000 || (code >= 4000 && code < 4500)
                    if code < 3000 {
                        // We expose codes defined by Centrifuge protocol, hiding details
                        // about transport-specific error codes. We may have extra optional
                        // transportCode field in the future.
                        code = 4
                    }
                    serverDisconnect = CentrifugeDisconnectOptions(code: UInt32(code), reason: err.message, reconnect: reconnect)
                } else {
                    serverDisconnect = CentrifugeDisconnectOptions(code: 4, reason: "connection closed", reconnect: true)
                }

                strongSelf.onClose(serverDisconnect: serverDisconnect)
            }
            ws.onData = { [weak self] data in
                guard let strongSelf = self else { return }
                strongSelf.onData(data: data)
            }
            strongSelf.conn = ws
            strongSelf.conn?.connect()
        }
    }

    /**
     Disconnect from server.
     */
    public func disconnect() {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.needReconnect = false
            strongSelf.close(code: 0, reason: "clean disconnect", reconnect: false)
        }
    }

    /**
     Send raw asynchronous (without waiting for a response) message to server.
     - parameter data: Data
     - parameter completion: Completion block
     */
    public func send(data: Data, completion: @escaping (Error?)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(err)
                    return
                }
                strongSelf.sendSend(data: data, completion: completion)
            })
        }
    }

    /**
     Publish message Data to channel.
     - parameter channel: String channel name
     - parameter data: Data message data
     - parameter completion: Completion block
     */
    public func publish(channel: String, data: Data, completion: @escaping (Result<CentrifugePublishResult, Error>)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                strongSelf.sendPublish(channel: channel, data: data, completion: { _, error in
                    guard self != nil else { return }
                    if let err = error {
                        completion(.failure(err))
                        return
                    }
                    completion(.success(CentrifugePublishResult()))
                })
            })
        }
    }

    /**
     Send RPC  command.
     - parameter method: String
     - parameter data: Data
     - parameter completion: Completion block
     */
    public func rpc(method: String = "", data: Data, completion: @escaping (Result<CentrifugeRpcResult, Error>)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                strongSelf.sendRPC(method: method, data: data, completion: {result, error in
                    if let err = error {
                        completion(.failure(err))
                        return
                    }
                    completion(.success(CentrifugeRpcResult(data: result!.data)))
                })
            })
        }
    }

    public func presence(channel: String, completion: @escaping (Result<CentrifugePresenceResult, Error>)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                strongSelf.sendPresence(channel: channel, completion: completion)
            })
        }
    }
    
    public func presenceStats(channel: String, completion: @escaping (Result<CentrifugePresenceStatsResult, Error>)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                strongSelf.sendPresenceStats(channel: channel, completion: completion)
            })
        }
    }
    
    public func history(channel: String, limit: Int32 = 0, since: CentrifugeStreamPosition? = nil, reverse: Bool = false, completion: @escaping (Result<CentrifugeHistoryResult, Error>)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.waitForConnect(completion: { [weak self] error in
                guard let strongSelf = self else { return }
                if let err = error {
                    completion(.failure(err))
                    return
                }
                strongSelf.sendHistory(channel: channel, limit: limit, since: since, reverse: reverse, completion: completion)
            })
        }
    }

    /**
     Create subscription object to specific channel with delegate
     - parameter channel: String
     - parameter delegate: CentrifugeSubscriptionDelegate
     - returns: CentrifugeSubscription
     */
    public func newSubscription(channel: String, delegate: CentrifugeSubscriptionDelegate) throws -> CentrifugeSubscription {
        defer { subscriptionsLock.unlock() }
        subscriptionsLock.lock()
        guard self.subscriptions.filter({ $0.channel == channel }).count == 0 else { throw CentrifugeError.duplicateSub }
        let sub = CentrifugeSubscription(centrifuge: self, channel: channel, delegate: delegate)
        self.subscriptions.append(sub)
        return sub
    }

    /**
     Try to get Subscription from internal client registry. Can return nil if Subscription
     does not exist yet.
     - parameter channel: String
     - returns: CentrifugeSubscription?
     */
    public func getSubscription(channel: String) -> CentrifugeSubscription? {
        defer { subscriptionsLock.unlock() }
        subscriptionsLock.lock()
        return self.subscriptions.first(where: { $0.channel == channel })
    }

    /**
     * Say Client that Subscription should be removed from the internal registry. Subscription will be
     * automatically unsubscribed before removing.
     - parameter sub: CentrifugeSubscription
     */
    public func removeSubscription(_ sub: CentrifugeSubscription) {
        defer { subscriptionsLock.unlock() }
        subscriptionsLock.lock()
        self.subscriptions
            .filter({ $0.channel == sub.channel })
            .forEach { sub in
                self.unsubscribe(sub: sub)
                sub.onRemove()
            }
        self.subscriptions.removeAll(where: { $0.channel == sub.channel })
    }
    
    /**
     * Get a map with all client-side suscriptions in client's internal registry.
     */
    public func getSubscriptions() -> [String: CentrifugeSubscription] {
        var subs = [String : CentrifugeSubscription]()
        defer { subscriptionsLock.unlock() }
        subscriptionsLock.lock()
        self.subscriptions.forEach { sub in
            subs[sub.channel] = sub
        }
        return subs
    }
}

internal extension CentrifugeClient {
    
    func refreshWithToken(token: String) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.token = token
            strongSelf.sendRefresh(token: token, completion: { result, error in
                if let _ = error {
                    strongSelf.close(code: 7, reason: "refresh error", reconnect: true)
                    return
                }
                if let res = result {
                    if res.expires {
                        strongSelf.startConnectionRefresh(ttl: res.ttl)
                    }
                }
            })
        }
    }
    
    func getSubscriptionToken(channel: String, completion: @escaping (String)->()) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            guard let client = strongSelf.client else { completion(""); return }
            strongSelf.delegateQueue.addOperation { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.onPrivateSub(
                    strongSelf,
                    CentrifugePrivateSubEvent(client: client, channel: channel)
                ) {[weak self] token in
                    guard let strongSelf = self else { return }
                    strongSelf.syncQueue.async { [weak self] in
                        guard let strongSelf = self else { return }
                        guard strongSelf.client == client else { return }
                        completion(token)
                    }
                }
            }
        }
    }

    func unsubscribe(sub: CentrifugeSubscription) {
        let channel = sub.channel
        if self.state == .connected {
            self.sendUnsubscribe(channel: channel, completion: { [weak self] _, error in
                guard let strongSelf = self else { return }
                if let _ = error {
                    strongSelf.close(code: 13, reason: "unsubscribe error", reconnect: true)
                    return
                }
            })
        }
    }

    func resubscribe() {
        subscriptionsLock.lock()
        for sub in self.subscriptions {
            sub.resubscribeIfNecessary()
        }
        subscriptionsLock.unlock()
    }
    
    func subscribe(channel: String, token: String, isRecover: Bool, streamPosition: StreamPosition, completion: @escaping (Centrifugal_Centrifuge_Protocol_SubscribeResult?, Error?)->()) {
        self.sendSubscribe(channel: channel, token: token, isRecover: isRecover, streamPosition: streamPosition, completion: completion)
    }
        
    func close(code: UInt32, reason: String, reconnect: Bool) {
        self.disconnectOpts = CentrifugeDisconnectOptions(code: code, reason: reason, reconnect: reconnect)
        self.conn?.disconnect()
    }
}

fileprivate extension CentrifugeClient {
    func log(_ items: Any) {
        print("CentrifugeClient: \n \(items)")
    }
}

fileprivate extension CentrifugeClient {
    func onOpen() {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.sendConnect(completion: { [weak self] res, error in
                guard let strongSelf = self else { return }
                if let err = error {
                    switch err {
                    case CentrifugeError.replyError(let code, let message):
                        if code == 109 {
                            strongSelf.delegateQueue.addOperation { [weak self] in
                                guard let strongSelf = self else { return }
                                strongSelf.delegate?.onRefresh(strongSelf, CentrifugeRefreshEvent()) {[weak self] token in
                                    guard let strongSelf = self else { return }
                                    if token != "" {
                                        strongSelf.token = token
                                    }
                                    strongSelf.close(code: 7, reason: message, reconnect: true)
                                    return
                                }
                            }
                        } else {
                            strongSelf.close(code: 6, reason: "connect error", reconnect: true)
                            return
                        }
                    default:
                        strongSelf.close(code: 6, reason: "connect error", reconnect: true)
                        return
                    }
                }
                
                if let result = res {
                    strongSelf.connecting = false
                    strongSelf.state = .connected
                    strongSelf.numReconnectAttempts = 0
                    strongSelf.client = result.client
                    strongSelf.delegateQueue.addOperation { [weak self] in
                        guard let strongSelf = self else { return }
                        strongSelf.delegate?.onConnect(strongSelf, CentrifugeConnectEvent(client: result.client))
                    }
                    for cb in strongSelf.connectCallbacks.values {
                        cb(nil)
                    }
                    strongSelf.connectCallbacks.removeAll(keepingCapacity: true)
                    // Process server-side subscriptions.
                    for (channel, subResult) in result.subs {
                        let isResubscribe = strongSelf.serverSubs[channel] != nil
                        strongSelf.serverSubs[channel] = serverSubscription(recoverable: subResult.recoverable, offset: subResult.offset, epoch: subResult.epoch)
                        let event = CentrifugeServerSubscribeEvent(channel: channel, resubscribe: isResubscribe, recovered: subResult.recovered)
                        strongSelf.delegateQueue.addOperation { [weak self] in
                            guard let strongSelf = self else { return }
                            strongSelf.delegate?.onSubscribe(strongSelf, event)
                            subResult.publications.forEach{ pub in
                                var info: CentrifugeClientInfo? = nil;
                                if pub.hasInfo {
                                    info = CentrifugeClientInfo(client: pub.info.client, user: pub.info.user, connInfo: pub.info.connInfo, chanInfo: pub.info.chanInfo)
                                }
                                let pubEvent = CentrifugeServerPublishEvent(channel: channel, data: pub.data, offset: pub.offset, info: info)
                                strongSelf.delegateQueue.addOperation { [weak self] in
                                    guard let strongSelf = self else { return }
                                    strongSelf.delegate?.onPublish(strongSelf, pubEvent)
                                }
                            }
                        }
                        for (channel, _) in strongSelf.serverSubs {
                            if result.subs[channel] == nil {
                                strongSelf.serverSubs.removeValue(forKey: channel)
                            }
                        }
                    }
                    // Resubscribe to client-side subscriptions.
                    strongSelf.resubscribe()
                    strongSelf.startPing()
                    if result.expires {
                        strongSelf.startConnectionRefresh(ttl: result.ttl)
                    }
                }
            })
        }
    }
    
    func onData(data: Data) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.handleData(data: data as Data)
        }
    }
    
    func onClose(serverDisconnect: CentrifugeDisconnectOptions?) {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }

            let disconnect: CentrifugeDisconnectOptions = serverDisconnect
                ?? strongSelf.disconnectOpts
            ?? CentrifugeDisconnectOptions(code: 4, reason: "connection closed", reconnect: true)

            strongSelf.connecting = false
            strongSelf.disconnectOpts = nil
            strongSelf.scheduleDisconnect(code: disconnect.code, reason: disconnect.reason, reconnect: disconnect.reconnect)
        }
    }
    
    private func nextCommandId() -> UInt32 {
        self.commandIdLock.lock()
        self.commandId += 1
        let cid = self.commandId
        self.commandIdLock.unlock()
        return cid
    }
        
    private func sendCommand(command: Centrifugal_Centrifuge_Protocol_Command, completion: @escaping (Centrifugal_Centrifuge_Protocol_Reply?, Error?)->()) {
        self.syncQueue.async {
            let commands: [Centrifugal_Centrifuge_Protocol_Command] = [command]
            do {
                let data = try CentrifugeSerializer.serializeCommands(commands: commands)
                self.conn?.write(data: data)
                self.waitForReply(id: command.id, completion: completion)
            } catch {
                completion(nil, error)
                return
            }
        }
    }
    
    private func sendCommandAsync(command: Centrifugal_Centrifuge_Protocol_Command) throws {
        let commands: [Centrifugal_Centrifuge_Protocol_Command] = [command]
        let data = try CentrifugeSerializer.serializeCommands(commands: commands)
        self.conn?.write(data: data)
    }
    
    private func waitForReply(id: UInt32, completion: @escaping (Centrifugal_Centrifuge_Protocol_Reply?, Error?)->()) {
        let timeoutTask = DispatchWorkItem { [weak self] in
            self?.opCallbacks[id] = nil
            completion(nil, CentrifugeError.timeout)
        }
        self.syncQueue.asyncAfter(deadline: .now() + self.config.timeout, execute: timeoutTask)
        
        self.opCallbacks[id] = { [weak self] rep in
            timeoutTask.cancel()
            
            self?.opCallbacks[id] = nil

            if let err = rep.error {
                completion(nil, err)
            } else {
                completion(rep.reply, nil)
            }
        }
    }
    
    private func waitForConnect(completion: @escaping (Error?)->()) {
        if !self.needReconnect {
            completion(CentrifugeError.clientDisconnected)
            return
        }
        if self.state == .connected {
            completion(nil)
            return
        }
        
        let uid = UUID().uuidString
        
        let timeoutTask = DispatchWorkItem { [weak self] in
            self?.connectCallbacks[uid] = nil
            completion(CentrifugeError.timeout)
        }
        self.syncQueue.asyncAfter(deadline: .now() + self.config.timeout, execute: timeoutTask)
        
        self.connectCallbacks[uid] = { error in
            timeoutTask.cancel()
            completion(error)
        }
    }
 
    private func scheduleReconnect() {
        self.syncQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.connecting = true
            let randomDouble = Double.random(in: 0.4...0.7)
            let delay = min(0.1 + pow(Double(strongSelf.numReconnectAttempts), 2) * randomDouble, strongSelf.config.maxReconnectDelay)
            strongSelf.numReconnectAttempts += 1
            strongSelf.syncQueue.asyncAfter(deadline: .now() + delay, execute: { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.syncQueue.async { [weak self] in
                    guard let strongSelf = self else { return }
                    if strongSelf.needReconnect {
                        strongSelf.conn?.connect()
                    } else {
                        strongSelf.connecting = false
                    }
                }
            })
        }
    }
    
    private func handlePub(channel: String, pub: Centrifugal_Centrifuge_Protocol_Publication) {
        subscriptionsLock.lock()
        let subs = self.subscriptions.filter({ $0.channel == channel })
        if subs.count == 0 {
            subscriptionsLock.unlock()
            if let _ = self.serverSubs[channel] {
                self.delegateQueue.addOperation {
                    var info: CentrifugeClientInfo? = nil;
                    if pub.hasInfo {
                        info = CentrifugeClientInfo(client: pub.info.client, user: pub.info.user, connInfo: pub.info.connInfo, chanInfo: pub.info.chanInfo)
                    }
                    let event = CentrifugeServerPublishEvent(channel: channel, data: pub.data, offset: pub.offset, info: info)
                    self.delegate?.onPublish(self, event)
                    if self.serverSubs[channel]?.recoverable == true && pub.offset > 0 {
                        self.serverSubs[channel]?.offset = pub.offset
                    }
                }
            }
            return
        }
        let sub = subs[0]
        subscriptionsLock.unlock()
        self.delegateQueue.addOperation {
            var info: CentrifugeClientInfo? = nil;
            if pub.hasInfo {
                info = CentrifugeClientInfo(client: pub.info.client, user: pub.info.user, connInfo: pub.info.connInfo, chanInfo: pub.info.chanInfo)
            }
            let event = CentrifugePublishEvent(data: pub.data, offset: pub.offset, info: info)
            sub.delegate?.onPublish(sub, event)
        }
        if pub.offset > 0 {
            sub.setLastOffset(pub.offset)
        }
    }
    
    private func handleJoin(channel: String, join: Centrifugal_Centrifuge_Protocol_Join) {
        subscriptionsLock.lock()
        let subs = self.subscriptions.filter({ $0.channel == channel })
        if subs.count == 0 {
            subscriptionsLock.unlock()
            if let _ = self.serverSubs[channel] {
                self.delegateQueue.addOperation {
                    let event = CentrifugeServerJoinEvent(channel: channel, client: join.info.client, user: join.info.user, connInfo: join.info.connInfo, chanInfo: join.info.chanInfo)
                    self.delegate?.onJoin(self, event)
                }
            }
            return
        }
        let sub = subs[0]
        subscriptionsLock.unlock()
        self.delegateQueue.addOperation {
            sub.delegate?.onJoin(sub, CentrifugeJoinEvent(client: join.info.client, user: join.info.user, connInfo: join.info.connInfo, chanInfo: join.info.chanInfo))
        }
    }
    
    private func handleLeave(channel: String, leave: Centrifugal_Centrifuge_Protocol_Leave) {
        subscriptionsLock.lock()
        let subs = self.subscriptions.filter({ $0.channel == channel })
        if subs.count == 0 {
            subscriptionsLock.unlock()
            if let _ = self.serverSubs[channel] {
                self.delegateQueue.addOperation {
                    let event = CentrifugeServerLeaveEvent(channel: channel, client: leave.info.client, user: leave.info.user, connInfo: leave.info.connInfo, chanInfo: leave.info.chanInfo)
                    self.delegate?.onLeave(self, event)
                }
            }
            return
        }
        let sub = subs[0]
        subscriptionsLock.unlock()
        self.delegateQueue.addOperation {
            sub.delegate?.onLeave(sub, CentrifugeLeaveEvent(client: leave.info.client, user: leave.info.user, connInfo: leave.info.connInfo, chanInfo: leave.info.chanInfo))
        }
    }
    
    private func handleUnsubscribe(channel: String, unsubscribe: Centrifugal_Centrifuge_Protocol_Unsubscribe) {
        subscriptionsLock.lock()
        let subs = self.subscriptions.filter({ $0.channel == channel })
        if subs.count == 0 {
            subscriptionsLock.unlock()
            if let _ = self.serverSubs[channel] {
                self.delegateQueue.addOperation {
                    let event = CentrifugeServerUnsubscribeEvent(channel: channel)
                    self.delegate?.onUnsubscribe(self, event)
                    self.serverSubs.removeValue(forKey: channel)
                }
            }
            return
        }
        let sub = subs[0]
        subscriptionsLock.unlock()
        sub.unsubscribe()
    }
    
    private func handleSubscribe(channel: String, sub: Centrifugal_Centrifuge_Protocol_Subscribe) {
        self.serverSubs[channel] = serverSubscription(recoverable: sub.recoverable, offset: sub.offset, epoch: sub.epoch)
        self.delegateQueue.addOperation {
            let event = CentrifugeServerSubscribeEvent(channel: channel, resubscribe: false, recovered: false)
            self.delegate?.onSubscribe(self, event)
        }
    }

    private func handleMessage(message: Centrifugal_Centrifuge_Protocol_Message) {
        self.delegateQueue.addOperation {
            self.delegate?.onMessage(self, CentrifugeMessageEvent(data: message.data))
        }
    }
    
    private func handleAsyncData(push: Centrifugal_Centrifuge_Protocol_Push) throws {
        let channel = push.channel
        if push.hasPub {
            let pub = push.pub
            self.handlePub(channel: channel, pub: pub)
        } else if push.hasJoin {
            let join = push.join
            self.handleJoin(channel: channel, join: join)
        } else if push.hasLeave {
            let leave = push.leave
            self.handleLeave(channel: channel, leave: leave)
        } else if push.hasUnsubscribe {
            let unsubscribe = push.unsubscribe
            self.handleUnsubscribe(channel: channel, unsubscribe: unsubscribe)
        } else if push.hasSubscribe {
            let sub = push.subscribe
            self.handleSubscribe(channel: channel, sub: sub)
        } else if push.hasMessage {
            let message = push.message
            self.handleMessage(message: message)
        } else if push.hasDisconnect {
            // TODO: handle disconnect push.
        }
    }
    
    private func handleData(data: Data) {
        guard let replies = try? CentrifugeSerializer.deserializeCommands(data: data) else { return }
        for reply in replies {
            if reply.id > 0 {
                self.opCallbacks[reply.id]?(CentrifugeResolveData(error: nil, reply: reply))
            } else {
                try? self.handleAsyncData(push: reply.push)
            }
        }
    }
    
    private func startPing() {
//        if self.config.pingInterval == 0 {
//            return
//        }
//        self.pingTimer = DispatchSource.makeTimerSource()
//        self.pingTimer?.setEventHandler { [weak self] in
//            guard let strongSelf = self else { return }
//            let params = Centrifugal_Centrifuge_Protocol_PingRequest()
//            do {
//                let paramsData = try params.serializedData()
//                let command = strongSelf.newCommand(method: .ping, params: paramsData)
//                strongSelf.sendCommand(command: command, completion: { [weak self] res, error in
//                    guard let strongSelf = self else { return }
//                    if let err = error {
//                        switch err {
//                        case CentrifugeError.timeout:
//                            strongSelf.close(code: 11, reason: "no ping", reconnect: true)
//                            return
//                        default:
//                            // Nothing to do.
//                            return
//                        }
//                    }
//                })
//            } catch {
//                return
//            }
//        }
//        self.pingTimer?.schedule(deadline: .now() + self.config.pingInterval, repeating: self.config.pingInterval)
//        self.pingTimer?.resume()
    }
    
    private func stopPing() {
        self.pingTimer?.cancel()
    }
    
    private func startConnectionRefresh(ttl: UInt32) {
        let refreshTask = DispatchWorkItem { [weak self] in
            self?.delegateQueue.addOperation {
                guard let strongSelf = self else { return }
                strongSelf.delegate?.onRefresh(strongSelf, CentrifugeRefreshEvent()) { [weak self] token in
                    guard let strongSelf = self else { return }
                    if token == "" {
                        return
                    }
                    strongSelf.refreshWithToken(token: token)
                }
            }
        }

        self.syncQueue.asyncAfter(deadline: .now() + Double(ttl), execute: refreshTask)
        self.refreshTask = refreshTask
    }
    
    private func stopConnectionRefresh() {
        self.refreshTask?.cancel()
    }
    
    private func scheduleDisconnect(code: UInt32, reason: String, reconnect: Bool) {
        let previousStatus = self.state
        self.state = .disconnected
        self.client = nil
        
        for resolveFunc in self.opCallbacks.values {
            resolveFunc(CentrifugeResolveData(error: CentrifugeError.clientDisconnected, reply: nil))
        }
        self.opCallbacks.removeAll(keepingCapacity: true)
        
        for resolveFunc in self.connectCallbacks.values {
            resolveFunc(CentrifugeError.clientDisconnected)
        }
        self.connectCallbacks.removeAll(keepingCapacity: true)
        
        subscriptionsLock.lock()
        for sub in self.subscriptions {
            if !reconnect {
                sub.setNeedRecover(false)
            }
            sub.moveToUnsubscribed()
        }
        subscriptionsLock.unlock()
        
        self.stopPing()
        
        self.stopConnectionRefresh()
        
        if previousStatus == .connected  {
            self.delegateQueue.addOperation { [weak self] in
                guard let strongSelf = self else { return }
                for (channel, _) in strongSelf.serverSubs {
                    let event = CentrifugeServerUnsubscribeEvent(channel: channel)
                    strongSelf.delegate?.onUnsubscribe(strongSelf, event)
                }
                strongSelf.delegate?.onDisconnect(
                    strongSelf,
                    CentrifugeDisconnectEvent(code: code, reason: reason, reconnect: reconnect)
                )
            }
        }
        
        if reconnect {
            self.scheduleReconnect()
        }
    }
    
    private func sendConnect(completion: @escaping (Centrifugal_Centrifuge_Protocol_ConnectResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_ConnectRequest()
        if self.token != nil {
            req.token = self.token!
        }
        if self.data != nil {
            req.data = self.data!
        }
        req.name = self.config.name
        req.version = self.config.version
        if !self.serverSubs.isEmpty {
            var subs = [String: Centrifugal_Centrifuge_Protocol_SubscribeRequest]()
            for (channel, serverSub) in self.serverSubs {
                var subRequest = Centrifugal_Centrifuge_Protocol_SubscribeRequest();
                subRequest.recover = serverSub.recoverable
                subRequest.offset = serverSub.offset
                subRequest.epoch = serverSub.epoch
                subs[channel] = subRequest
            }
            req.subs = subs
        }
        
        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.connect = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                completion(rep.connect, nil)
            }
        })
    }
    
    private func sendRefresh(token: String, completion: @escaping (Centrifugal_Centrifuge_Protocol_RefreshResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_RefreshRequest()
        req.token = token

        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.refresh = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                completion(rep.refresh, nil)
            }
        })
    }
    
    private func sendUnsubscribe(channel: String, completion: @escaping (Centrifugal_Centrifuge_Protocol_UnsubscribeResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_UnsubscribeRequest()
        req.channel = channel

        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.unsubscribe = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                completion(rep.unsubscribe, nil)
            }
        })
    }
    
    private func sendSubscribe(channel: String, token: String, isRecover: Bool, streamPosition: StreamPosition, completion: @escaping (Centrifugal_Centrifuge_Protocol_SubscribeResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_SubscribeRequest()
        req.channel = channel
        if isRecover {
            req.recover = true
            req.epoch = streamPosition.epoch
            req.offset = streamPosition.offset
        }

        if token != "" {
            req.token = token
        }
        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.subscribe = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                completion(rep.subscribe, nil)
            }
        })
    }
    
    private func sendPublish(channel: String, data: Data, completion: @escaping (Centrifugal_Centrifuge_Protocol_PublishResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_PublishRequest()
        req.channel = channel
        req.data = data

        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.publish = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                completion(rep.publish, nil)
            }
        })
    }
    
    private func sendHistory(channel: String, limit: Int32 = 0, since: CentrifugeStreamPosition?, reverse: Bool = false, completion: @escaping (Result<CentrifugeHistoryResult, Error>)->()) {
        var req = Centrifugal_Centrifuge_Protocol_HistoryRequest()
        req.channel = channel
        req.limit = limit
        req.reverse = reverse
        if since != nil {
            var sp = Centrifugal_Centrifuge_Protocol_StreamPosition()
            sp.offset = since!.offset
            sp.epoch = since!.epoch
            req.since = sp
        }
        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.history = req
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(.failure(err))
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(.failure(CentrifugeError.replyError(code: rep.error.code, message: rep.error.message)))
                    return
                }
                let result = rep.history
                var pubs = [CentrifugePublication]()
                for pub in result.publications {
                    var clientInfo: CentrifugeClientInfo?
                    if pub.hasInfo {
                        clientInfo = CentrifugeClientInfo(client: pub.info.client, user: pub.info.user, connInfo: pub.info.connInfo, chanInfo: pub.info.chanInfo)
                    }
                    pubs.append(CentrifugePublication(offset: pub.offset, data: pub.data, clientInfo: clientInfo))
                }
                completion(.success(CentrifugeHistoryResult(publications: pubs, offset: result.offset, epoch: result.epoch)))
            }
        })
    }
    
    private func sendPresence(channel: String, completion: @escaping (Result<CentrifugePresenceResult, Error>)->()) {
        var req = Centrifugal_Centrifuge_Protocol_PresenceRequest()
        req.channel = channel

        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.presence = req
        
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(.failure(err))
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(.failure(CentrifugeError.replyError(code: rep.error.code, message: rep.error.message)))
                    return
                }
                let result = rep.presence
                var presence = [String: CentrifugeClientInfo]()
                for (client, info) in result.presence {
                    presence[client] = CentrifugeClientInfo(client: info.client, user: info.user, connInfo: info.connInfo, chanInfo: info.chanInfo)
                }
                completion(.success(CentrifugePresenceResult(presence: presence)))
            }
        })
    }
    
    private func sendPresenceStats(channel: String, completion: @escaping (Result<CentrifugePresenceStatsResult, Error>)->()) {
        var req = Centrifugal_Centrifuge_Protocol_PresenceStatsRequest()
        req.channel = channel
        
        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.presenceStats = req
        
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(.failure(err))
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(.failure(CentrifugeError.replyError(code: rep.error.code, message: rep.error.message)))
                    return
                }
                let result = rep.presenceStats
                let stats = CentrifugePresenceStatsResult(numClients: result.numClients, numUsers: result.numUsers)
                completion(.success(stats))
            }
        })
    }
    
    private func sendRPC(method: String, data: Data, completion: @escaping (Centrifugal_Centrifuge_Protocol_RPCResult?, Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_RPCRequest()
        req.data = data
        req.method = method

        var command = Centrifugal_Centrifuge_Protocol_Command()
        command.id = self.nextCommandId()
        command.rpc = req
        
        self.sendCommand(command: command, completion: { [weak self] reply, error in
            guard self != nil else { return }
            if let err = error {
                completion(nil, err)
                return
            }
            if let rep = reply {
                if rep.hasError {
                    completion(nil, CentrifugeError.replyError(code: rep.error.code, message: rep.error.message))
                    return
                }
                let result = rep.rpc
                completion(result, nil)
            }
        })
    }
    
    private func sendSend(data: Data, completion: @escaping (Error?)->()) {
        var req = Centrifugal_Centrifuge_Protocol_SendRequest()
        req.data = data
        do {
            var command = Centrifugal_Centrifuge_Protocol_Command()
            command.send = req
            try self.sendCommandAsync(command: command)
            completion(nil)
        } catch {
            completion(error)
        }
    }
}
