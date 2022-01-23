//
//  Delegate.swift
//  SwiftCentrifuge
//
//  Created by Alexander Emelin on 03/01/2019.
//  Copyright © 2019 Alexander Emelin. All rights reserved.
//

import Foundation

public struct CentrifugeConnectEvent{
    public var client: String
}

public struct CentrifugeDisconnectEvent{
    public var code: UInt32 // Used only for client protocol >= v2.
    public var reason: String
    public var reconnect: Bool
}

public struct CentrifugeRefreshEvent {}

public struct CentrifugeJoinEvent {
    public var client: String
    public var user: String
    public var connInfo: Data
    public var chanInfo: Data
}

public struct CentrifugeLeaveEvent {
    public var client: String
    public var user: String
    public var connInfo: Data
    public var chanInfo: Data
}

public struct CentrifugeMessageEvent {
    public var data: Data
}

public struct CentrifugePublishEvent {
    public var data: Data
    public var offset: UInt64
    var info: CentrifugeClientInfo?
}

public struct CentrifugePrivateSubEvent {
    public var client: String
    public var channel: String
}

public struct CentrifugeSubscribeErrorEvent {
    public var code: UInt32
    public var message: String
}

public struct CentrifugeSubscribeSuccessEvent {
    public var resubscribe = false
    public var recovered = false
}

public struct CentrifugeUnsubscribeEvent {}

public struct CentrifugeServerSubscribeEvent {
    public var channel: String
    public var resubscribe = false
    public var recovered = false
}

public struct CentrifugeServerUnsubscribeEvent {
    public var channel: String
}

public struct CentrifugeServerPublishEvent {
    public var channel: String
    public var data: Data
    public var offset: UInt64
    var info: CentrifugeClientInfo?
}

public struct CentrifugeServerJoinEvent {
    public var channel: String
    public var client: String
    public var user: String
    public var connInfo: Data?
    public var chanInfo: Data?
}

public struct CentrifugeServerLeaveEvent {
    public var channel: String
    public var client: String
    public var user: String
    public var connInfo: Data?
    public var chanInfo: Data?
}

public protocol CentrifugeClientDelegate: class {
    func onConnect(_ client: CentrifugeClient, _ event: CentrifugeConnectEvent)
    func onDisconnect(_ client: CentrifugeClient, _ event: CentrifugeDisconnectEvent)
    func onPrivateSub(_ client: CentrifugeClient, _ event: CentrifugePrivateSubEvent, completion: @escaping (_ token: String) -> ())
    func onRefresh(_ client: CentrifugeClient, _ event: CentrifugeRefreshEvent, completion: @escaping (_ token: String) -> ())
    func onMessage(_ client: CentrifugeClient, _ event: CentrifugeMessageEvent)
    func onSubscribe(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribeEvent)
    func onPublish(_ client: CentrifugeClient, _ event: CentrifugeServerPublishEvent)
    func onUnsubscribe(_ client: CentrifugeClient, _ event: CentrifugeServerUnsubscribeEvent)
    func onJoin(_ client: CentrifugeClient, _ event: CentrifugeServerJoinEvent)
    func onLeave(_ client: CentrifugeClient, _ event: CentrifugeServerLeaveEvent)
}

public extension CentrifugeClientDelegate {
    func onConnect(_ client: CentrifugeClient, _ event: CentrifugeConnectEvent) {}
    func onDisconnect(_ client: CentrifugeClient, _ event: CentrifugeDisconnectEvent) {}
    func onPrivateSub(_ client: CentrifugeClient, _ event: CentrifugePrivateSubEvent, completion: @escaping (_ token: String) -> ()) {
        completion("")
    }
    func onRefresh(_ client: CentrifugeClient, _ event: CentrifugeRefreshEvent, completion: @escaping (_ token: String) -> ()) {
        completion("")
    }
    func onMessage(_ client: CentrifugeClient, _ event: CentrifugeMessageEvent) {}
    func onSubscribe(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribeEvent) {}
    func onPublish(_ client: CentrifugeClient, _ event: CentrifugeServerPublishEvent) {}
    func onUnsubscribe(_ client: CentrifugeClient, _ event: CentrifugeServerUnsubscribeEvent) {}
    func onJoin(_ client: CentrifugeClient, _ event: CentrifugeServerJoinEvent) {}
    func onLeave(_ client: CentrifugeClient, _ event: CentrifugeServerLeaveEvent) {}
}

public protocol CentrifugeSubscriptionDelegate: class {
    func onPublish(_ sub: CentrifugeSubscription, _ event: CentrifugePublishEvent)
    func onJoin(_ sub: CentrifugeSubscription, _ event: CentrifugeJoinEvent)
    func onLeave(_ sub: CentrifugeSubscription, _ event: CentrifugeLeaveEvent)
    func onSubscribeError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribeErrorEvent)
    func onSubscribeSuccess(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribeSuccessEvent)
    func onUnsubscribe(_ sub: CentrifugeSubscription, _ event: CentrifugeUnsubscribeEvent)
}

public extension CentrifugeSubscriptionDelegate {
    func onPublish(_ sub: CentrifugeSubscription, _ event: CentrifugePublishEvent) {}
    func onJoin(_ sub: CentrifugeSubscription, _ event: CentrifugeJoinEvent) {}
    func onLeave(_ sub: CentrifugeSubscription, _ event: CentrifugeLeaveEvent) {}
    func onSubscribeError(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribeErrorEvent) {}
    func onSubscribeSuccess(_ sub: CentrifugeSubscription, _ event: CentrifugeSubscribeSuccessEvent) {}
    func onUnsubscribe(_ sub: CentrifugeSubscription, _ event: CentrifugeUnsubscribeEvent) {}
}
