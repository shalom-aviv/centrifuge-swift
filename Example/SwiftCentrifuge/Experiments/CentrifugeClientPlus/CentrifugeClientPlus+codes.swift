//
//  CentrifugeClientPlus+codes.swift
//  SwiftCentrifuge
//
//  Created by shalom-aviv on 2/20/25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import Foundation
import SwiftCentrifuge

public extension CentrifugeClientPlus {
    enum DisconnectedCode {
        static let disconnectCalled: UInt32 = 0
    }

    enum ConnectingCode {
        static let connectCalled: UInt32 = 0
    }
}

extension CentrifugeDisconnectedEvent {
    static let disconnectCalled = CentrifugeDisconnectedEvent(code: CentrifugeClientPlus.DisconnectedCode.disconnectCalled, reason: "disconnect called")
}

extension CentrifugeConnectingEvent {
    static let connectCalled = CentrifugeConnectingEvent(code: CentrifugeClientPlus.ConnectingCode.connectCalled, reason: "pause called")
}
