//
//  SNLExecutorPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 20.12.2019.
//

import Foundation

public protocol SNLExecutorPrtcl {

    var resource: SNLResourcePrtcl { get set }
    var method: SNLHTTPMethod { get set }
    var path: URL { get set }
    var dynamicPathsParts: SNLDynamicParts? { get set }
    var targetHeaders: SNLHeader? { get set }
    var targetParams: SNLParams? { get set }
    var requestHeaders: SNLHeader? { get set }
    var requestParams: SNLParams? { get set }
    var body: SNLBody? { get set }
    var timeoutIntervalForRequest: Double? { get set }
    var timeoutIntervalForResource: Double? { get set }

    func execute(debug: Bool, _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void)

    func execute(_ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void)

    func execute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    )

    func execute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    )
    

    @discardableResult
    func execute(debug: Bool) async throws -> SNLHTTPResponse

    @discardableResult
    func execute() async throws -> SNLHTTPResponse
    

    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> (model: ResponseModel, response: SNLHTTPResponse)

    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> (model: ResponseModel, response: SNLHTTPResponse)

    @discardableResult
    func modelExecute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> ResponseModel

    @discardableResult
    func modelExecute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> ResponseModel
    

    func waitExecute(debug: Bool, _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void)

    func waitExecute(_ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void)

    func waitExecute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    )

    func waitExecute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    )
}
