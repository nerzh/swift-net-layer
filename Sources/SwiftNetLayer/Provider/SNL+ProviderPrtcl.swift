//
//  SNL+ProviderPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation

public protocol SNLProviderPrtcl: Sendable {
    
    init()
    
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void
    )
    
    @discardableResult
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool
    ) async throws -> SNLHTTPResponse
}


public extension SNLProviderPrtcl {
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void = { _, _ in }
    ) {
        SNLProvider().executeRequest(resource: resource, request: request, debug: debug, handler)
    }

    @discardableResult
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false
    ) async throws -> SNLHTTPResponse {
        try await SNLProvider().executeRequest(resource: resource, request: request, debug: debug)
    }
}
