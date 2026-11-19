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

    public init(requestLimit: UInt = 100, timeRangeLimitSecond: UInt = 1) {
        self.requestLimit = requestLimit
        self.timeRangeLimitSecond = timeRangeLimitSecond
    }

    mutating func acquireRequestSlotOrRetryAt(at uptimeNanoseconds: UInt64) -> UInt64? {
        let nanosecondsPerSecond: UInt64 = 1_000_000_000
        let windowSeconds = UInt64(timeRangeLimitSecond)
        if uptimeNanoseconds < windowStartNanoseconds ||
            (uptimeNanoseconds - windowStartNanoseconds) / nanosecondsPerSecond >= windowSeconds {
            windowStartNanoseconds = uptimeNanoseconds
            requestCounter = 0
        }

        guard requestCounter < requestLimit else {
            guard windowSeconds > 0 else { return .max }
            let (windowNanoseconds, durationOverflow) = windowSeconds.multipliedReportingOverflow(by: nanosecondsPerSecond)
            let (deadline, deadlineOverflow) = windowStartNanoseconds.addingReportingOverflow(windowNanoseconds)
            return durationOverflow || deadlineOverflow ? .max : deadline
        }
        requestCounter += 1
        return nil
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
    
    public let requestPerSecondOptions: SafeValue<RequestPerSecondOptions>?

    public func acquireRequestSlotOrRetryAt() -> UInt64? {
        requestPerSecondOptions?.change { options in
            options.acquireRequestSlotOrRetryAt(at: DispatchTime.now().uptimeNanoseconds)
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
