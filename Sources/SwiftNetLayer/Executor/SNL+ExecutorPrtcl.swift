//
//  SNLExecutorPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 20.12.2019.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

    func execute(debug: Bool, _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws
    func execute(_ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws

    func execute<ResponseModel: Decodable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void
    ) throws
    func execute<ResponseModel: Decodable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void
    ) throws
    
    @discardableResult
    func execute(debug: Bool) async throws -> (Data, URLResponse)
    @discardableResult
    func execute() async throws -> (Data, URLResponse)
    @discardableResult
    func execute(debug: Bool) async throws -> Data
    @discardableResult
    func execute() async throws -> Data
    
    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> (ResponseModel, URLResponse)
    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> ResponseModel
    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> (ResponseModel, URLResponse)
    @discardableResult
    func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> ResponseModel
    
    func waitExecute(debug: Bool, _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws
    func waitExecute(_ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws

    func waitExecute<ResponseModel: Decodable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void
    ) throws
    func waitExecute<ResponseModel: Decodable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void
    ) throws
}
