//
//  Untitled.swift
//  SwiftCentrifuge
//
//  Created by Andrei Pachtarou on 2/20/25.
//

import SwiftCentrifuge

extension CentrifugeClient: Client {}
extension CentrifugeClientPlus: Client {}


extension CentrifugeClient {
    /// Static constructor that create CentrifugeClient and return it as Client protocol
    ///
    /// - Parameters:
    ///   - url: protobuf URL endpoint of Centrifugo/Centrifuge.
    ///   - config: config object.
    ///   - delegate: delegate protocol implementation to react on client events.
    static func newClient(endpoint: String, config: CentrifugeClientConfig, delegate: CentrifugeClientDelegate? = nil) -> Client {
        CentrifugeClient(
            endpoint: endpoint,
            config: config,
            delegate: delegate
        )
    }

    /// Static constructor that create CentrifugeClient and return it as Client protocol
    ///
    /// - Parameters:
    ///   - url: protobuf URL endpoint of Centrifugo/Centrifuge.
    ///   - config: config object.
    ///   - delegate: delegate protocol implementation to react on client events.
    static func newClientPlus(endpoint: String, config: CentrifugeClientConfig, delegate: CentrifugeClientDelegate? = nil) -> Client {
        CentrifugeClientPlus(
            endpoint: endpoint,
            config: config,
            delegate: delegate
        )
    }
}
