//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
import SwiftExtensionsPack

open class SNLTarget: SNLTargetPrtcl {

    public var resource: SNLResourcePrtcl
    public var path: URL
    public var headers: [String: String]?
    public var params: [String: Any]?

    required public init(resource: SNLResourcePrtcl,
                         path: String,
                         headers: [String: String]? = nil,
                         params: [String: Any]? = nil)
    {
        self.resource = resource
        guard let pathUrl = URL(string: path) else { fatalError("SNLTarget: pathUrl") }
        self.path = pathUrl
        self.headers = headers
        self.params = params
    }

    public func makeExecutor(target: SNLTargetPrtcl,
                             resource: SNLResourcePrtcl,
                             method: SNLHTTPMethod,
                             dynamicPathsParts: SNLDynamicParts? = nil,
                             requestHeaders: SNLHeader? = nil,
                             requestParams: SNLParams? = nil,
                             body: SNLBody? = nil,
                             timeoutIntervalForRequest: Double? = nil,
                             timeoutIntervalForResource: Double? = nil
    ) -> SNLExecutorPrtcl {
        return SNLExecutor(resource: resource,
                           method: method,
                           path: path,
                           dynamicPathsParts: dynamicPathsParts,
                           targetHeaders: target.headers,
                           targetParams: target.params,
                           requestHeaders: requestHeaders,
                           requestParams: requestParams,
                           body: body,
                           timeoutIntervalForRequest: timeoutIntervalForRequest,
                           timeoutIntervalForResource: timeoutIntervalForResource)
    }
}
