//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Dispatch
import Foundation
import SwiftExtensionsPack

public struct RequestPerSecondOptions {
    var requestCounter: UInt = .init(0)
    var windowStartNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    public var requestLimit: UInt
    public var timeRangeLimitSecond: UInt
    /// nanoseconds - delay before retry request; default: 0.01 s
    public var retryDelaySecond: UInt32
    
    public init(requestLimit: UInt = 100, timeRangeLimitSecond: UInt = 1, retryDelaySecond: UInt32 = 10_000_000) {
        self.requestLimit = requestLimit
        self.timeRangeLimitSecond = timeRangeLimitSecond
        self.retryDelaySecond = retryDelaySecond
    }

    mutating func allowRequest(at uptimeNanoseconds: UInt64) -> Bool {
        if uptimeNanoseconds < windowStartNanoseconds ||
            (uptimeNanoseconds - windowStartNanoseconds) / 1_000_000_000 >= UInt64(timeRangeLimitSecond) {
            windowStartNanoseconds = uptimeNanoseconds
            requestCounter = 0
        }

        guard requestCounter < requestLimit else { return false }
        requestCounter += 1
        return true
    }
}

open class SNLResource: SNLResourcePrtcl, @unchecked Sendable {
    public let provider: SNLProviderPrtcl
    public let `protocol`: SNLProtocolType
    public let domain: String
    public let version: String?
    public let defaultHeaders: SNLHeader?
    public let defaultParams: SafeValue<[String: Any]?>
    public var url: URL {
        let version = self.version != nil ? "/\(self.version!)" : ""
        guard let url = URL(string: "\(`protocol`)://\(domain)\(version)") else { fatalError("NetResource: Bad URL") }
        return url
    }
    
    /// Request Per Second WatchDog
    public let requestPerSecondOptions: SafeValue<RequestPerSecondOptions>?
    public var allowRequest: Bool {
        guard let requestPerSecondOptions else { return true }
        return requestPerSecondOptions.change { options in
            options.allowRequest(at: DispatchTime.now().uptimeNanoseconds)
        }
    }

    public init(
        provider: SNLProviderPrtcl = SNLProvider(),
        protocol: SNLProtocolType = .http,
        domain: String,
        version: String? = nil,
        defaultHeaders: SNLHeader? = nil,
        defaultParams: [String: Any]? = nil,
        requestPerSecondOptions: SafeValue<RequestPerSecondOptions>? = nil
    ) {
        self.provider = provider
        self.protocol = `protocol`
        self.domain = domain
        self.version = version
        self.defaultHeaders = defaultHeaders
        self.defaultParams = .init(defaultParams)
        self.requestPerSecondOptions = requestPerSecondOptions
    }
}
