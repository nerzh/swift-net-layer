//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation

public protocol SNLTargetPrtcl {

    var resource: SNLResourcePrtcl { get set }
    /// /users/:id
    var path: URL { get set }
    var headers: [String: String]? { get set }
    var params: [String: Any]? { get set }

    init(
        resource: SNLResourcePrtcl,
        path: String,
        headers: [String: String]?,
        params: [String: Any]?
    )

    func makeExecutor(
        target: SNLTargetPrtcl,
        resource: SNLResourcePrtcl,
        method: SNLHTTPMethod,
        dynamicPathsParts: SNLDynamicParts?,
        requestHeaders: SNLHeader?,
        requestParams: SNLParams?,
        body: SNLBody?,
        timeoutIntervalForRequest: Double?,
        timeoutIntervalForResource: Double?
    ) -> SNLExecutorPrtcl
}
