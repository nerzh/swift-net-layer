//
//  SNL+ProviderPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SNLProviderPrtcl: Sendable {
    
    init()
    
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void
    ) throws
    
    @discardableResult
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool
    ) async throws -> (Data, URLResponse)
}


public extension SNLProviderPrtcl {
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false,
        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void = { _, _, _ in }
    ) throws {
        try SNLProvider().executeRequest(resource: resource, request: request, debug: debug, handler)
    }

    @discardableResult
    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false
    ) async throws -> (Data, URLResponse) {
        try await SNLProvider().executeRequest(resource: resource, request: request, debug: debug)
    }
}
