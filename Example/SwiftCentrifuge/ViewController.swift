//
//  ViewController.swift
//  CentrifugePlayground
//
//  Created by Alexander Emelin on 03/01/2019.
//  Copyright © 2019 Alexander Emelin. All rights reserved.
//

import UIKit
import SwiftCentrifuge

enum RunParams {
    static let url = "ws://127.0.0.1:8000/connection/websocket?cf_protocol=protobuf"
    
    static let useNativeWebSocket = false

    static let authTokenInHeaders: String? = nil
    static let newAuthTokenInHeaders: String? = nil

    static let authHeaderKey = "Authorization"
    static func authHeaderValue(token: String) -> String { "Bearer \(token)" }

    static let failedMiddlewearAuthorization_StatusCode: Int? = nil
}

class ViewController: UIViewController {
    
    @IBOutlet weak var clientState: UILabel!
    @IBOutlet weak var lastMessage: UILabel!
    @IBOutlet weak var newMessage: UITextField!
    @IBOutlet weak var connectButton: UIButton!
    
    private var needUpdateConfigParams = false
    private var client: CentrifugeClient?
    private var sub: CentrifugeSubscription?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(self.disconnectClient(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.connectClient(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let config = CentrifugeClientConfig(
            headers: headers(token: RunParams.authHeaderKey),
            token: "",
            useNativeWebSocket: RunParams.useNativeWebSocket,
            tokenGetter: self,
            configUpdateGetter: self,
            logger: PrintLogger()
        )


        self.client = CentrifugeClient(endpoint: RunParams.url, config: config, delegate: self)

        do {
            sub = try self.client?.newSubscription(channel: "chat:index", delegate: self)
            sub!.subscribe()
        } catch {
            print("Can not create subscription: \(error)")
            return
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        client?.connect()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc func disconnectClient(_ notification: Notification) {
        client?.disconnect()
    }
    
    @objc func connectClient(_ notification: Notification) {
        client?.connect()
    }

    @IBAction func send(_ sender: Any) {
        let data = ["input": self.newMessage.text ?? ""]
        self.newMessage.text = ""
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) else {return}
        sub?.publish(data: jsonData, completion: { result in
            switch result {
            case .success(_):
                break
            case .failure(let err):
                print("Unexpected publish error: \(err)")
            }
        })
    }

    @IBAction func connect(_ sender: Any) {
        let state = self.client?.state;
        if state == .connecting || state == .connected {
            self.client?.disconnect()
            DispatchQueue.main.async { [weak self] in
                self?.clientState.text = "Disconnected"
                self?.connectButton.setTitle("Connect", for: .normal)
            }
        } else {
            self.client?.connect()
            DispatchQueue.main.async { [weak self] in
                self?.clientState.text = "Connecting"
                self?.connectButton.setTitle("Disconnect", for: .normal)
            }
        }
    }
}

extension ViewController: CentrifugeConnectionTokenGetter {
    func getConnectionToken(_ event: CentrifugeConnectionTokenEvent, completion: @escaping (Result<String, Error>) -> ()) {
        getNewToken(completion: completion)
    }
        
    func getNewToken(completion: @escaping (Result<String, Error>) -> ()) {
        guard let newToken = RunParams.newAuthTokenInHeaders else {
            completion(.failure(CentrifugeError.unauthorized))
            return
        }
        completion(.success(newToken))
        return
    }
}


extension ViewController: CentrifugeUpdateConnectionConfigGetter {
    func getConnectionConfigUpdate(completion: @escaping (Result<CentrifugeUpdateClientConfig?, Error>) -> ()) {
        getNewToken { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let newToken):
                let updateHeaders = self.headers(token: newToken) as [String: String?]
                completion(.success(CentrifugeUpdateClientConfig(headers: updateHeaders)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

extension ViewController: CentrifugeClientDelegate {
    func onUpdateClientConfigParams(_ client: CentrifugeClient) -> Bool {
        let result = needUpdateConfigParams
        needUpdateConfigParams = false
        return result
    }
    
    func onConnected(_ c: CentrifugeClient, _ e: CentrifugeConnectedEvent) {
        print("connected with id", e.client)
        DispatchQueue.main.async { [weak self] in
            self?.clientState.text = "Connected"
            self?.connectButton.setTitle("Disconnect", for: .normal)
        }
    }
    
    func onDisconnected(_ c: CentrifugeClient, _ e: CentrifugeDisconnectedEvent) {
        print("disconnected with code", e.code, "and reason", e.reason)
        DispatchQueue.main.async { [weak self] in
            self?.clientState.text = "Disconnected"
            self?.connectButton.setTitle("Connect", for: .normal)
        }
    }

    func onConnecting(_ c: CentrifugeClient, _ e: CentrifugeConnectingEvent) {
        print("connecting with code", e.code, "and reason", e.reason)
        DispatchQueue.main.async { [weak self] in
            self?.clientState.text = "Connecting"
            self?.connectButton.setTitle("Disconnect", for: .normal)
        }
    }

    func onSubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribedEvent) {
        print("server-side subscribe to", event.channel, "recovered", event.recovered)
    }

    func onSubscribing(_ client: CentrifugeClient, _ event: CentrifugeServerSubscribingEvent) {
        print("server-side subscribing to", event.channel)
    }
    
    func onUnsubscribed(_ client: CentrifugeClient, _ event: CentrifugeServerUnsubscribedEvent) {
        print("server-side unsubscribe from", event.channel)
    }

    func onPublication(_ client: CentrifugeClient, _ event: CentrifugeServerPublicationEvent) {
        print("server-side publication from", event.channel, "offset", event.offset)
    }
    
    func onJoin(_ client: CentrifugeClient, _ event: CentrifugeServerJoinEvent) {
        print("server-side join in", event.channel, "client", event.client)
    }

    func onLeave(_ client: CentrifugeClient, _ event: CentrifugeServerLeaveEvent) {
        print("server-side leave in", event.channel, "client", event.client)
    }
    
    func onError(_ client: CentrifugeClient, _ event: CentrifugeErrorEvent) {
        ///SPIKE:
        /// WSError - made public to get access for server status code
        guard
            case CentrifugeError.transportError(let error) = event.error,
            let err = error as? WSError,
            err.type == .upgradeError,
            err.code ==  RunParams.failedMiddlewearAuthorization_StatusCode
        else {
            print("client error \(event.error)")
            return
        }

        needUpdateConfigParams = true
    }
}

extension ViewController: CentrifugeSubscriptionDelegate {
    func onSubscribed(_ s: CentrifugeSubscription, _ e: CentrifugeSubscribedEvent) {
        print("successfully subscribed to channel \(s.channel), was recovering \(e.wasRecovering), recovered \(e.recovered)")
        s.presence(completion: { result in
            switch result {
            case .success(let presence):
                print(presence)
            case .failure(let err):
                print("Unexpected presence error: \(err)")
            }
        })
        s.history(limit: 10, completion: { result in
            switch result {
            case .success(let res):
                print("Num publications returned: \(res.publications.count)")
            case .failure(let err):
                print("Unexpected history error: \(err)")
            }
        })
    }

    func onSubscribing(_ s: CentrifugeSubscription, _ e: CentrifugeSubscribingEvent) {
        print("subscribing to channel", s.channel, e.code, e.reason)
    }
    
    func onUnsubscribed(_ s: CentrifugeSubscription, _ e: CentrifugeUnsubscribedEvent) {
        print("unsubscribed from channel", s.channel, e.code, e.reason)
    }
    
    func onError(_ s: CentrifugeSubscription, _ e: CentrifugeSubscriptionErrorEvent) {
        print("subscription error: \(e.error)")
    }
    
    func onPublication(_ s: CentrifugeSubscription, _ e: CentrifugePublicationEvent) {
        let data = String(data: e.data, encoding: .utf8) ?? ""
        print("message from channel", s.channel, data)
        DispatchQueue.main.async { [weak self] in
            self?.lastMessage.text = data
        }
    }
    
    func onJoin(_ s: CentrifugeSubscription, _ e: CentrifugeJoinEvent) {
        print("client joined channel \(s.channel), user ID \(e.user)")
    }
    
    func onLeave(_ s: CentrifugeSubscription, _ e: CentrifugeLeaveEvent) {
        print("client left channel \(s.channel), user ID \(e.user)")
    }
}

extension ViewController {
    func headers(token: String?) -> [String: String] {
        guard let token else {
            return [:]
        }
        return [RunParams.authHeaderKey: RunParams.authHeaderValue(token: token)]
    }
}
