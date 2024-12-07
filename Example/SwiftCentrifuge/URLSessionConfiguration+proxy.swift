//
//  URLSessionConfiguration+proxy.swift
//  SwiftCentrifuge_Example
//
//  Created by Andrey Pochtarev on 07.12.2024.
//  Copyright © 2024 CocoaPods. All rights reserved.
//

import Foundation
import Network

extension URLSessionConfiguration {
    struct SOCKS5ProxyParams: Equatable {
        let host: String
        let port: UInt16

        init?(host: String, port: UInt16) {
            guard IPv4Address(host) != nil else { return nil }
            self.host = host
            self.port = port
        }
    }

    func set(socks5ProxyParams: SOCKS5ProxyParams) {
        let host = socks5ProxyParams.host
        let port = socks5ProxyParams.port

        if #available(iOS 17.0, *) {
            let endpoint: NWEndpoint = .hostPort(
                host: .init(socks5ProxyParams.host),
                port: .init(integerLiteral: socks5ProxyParams.port)
            )
            self.proxyConfigurations = [.init(socksv5Proxy: endpoint)]
        } else {
            /// iOs with version lower than 17 hs problem with proxing.
            /// They do not handle system proxy params. There several solutions
            /// - setup proxy params by hand in UI and configure connection (We use this approach in this example)
            /// - get system proxy params  and use them to configure connection
            [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port,
                kCFStreamPropertySOCKSVersion: kCFStreamSocketSOCKSVersion5,
            ].forEach {
                self.connectionProxyDictionary?[$0.key] = $0.value
            }
        }
    }
}
