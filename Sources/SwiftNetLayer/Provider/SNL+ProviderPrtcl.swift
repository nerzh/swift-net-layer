//
//  SNL+ProviderPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation

public protocol SNLProviderPrtcl: Sendable {
    
    init()

    var callbackContext: SNLCallbackContext { get }
    
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
