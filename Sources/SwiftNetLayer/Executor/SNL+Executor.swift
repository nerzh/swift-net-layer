//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 19.12.2019.
//

import Foundation
import SwiftExtensionsPack
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SNLExecutor: SNLExecutorPrtcl {
    public var resource: SNLResourcePrtcl
    public var method: SNLHTTPMethod
    public var path: URL
    public var multipart: Bool
    public var dynamicPathsParts: SNLDynamicParts?
    public var targetHeaders: SNLHeader?
    public var targetParams: SNLParams?
    public var requestHeaders: SNLHeader?
    public var requestParams: SNLParams?
    public var body: SNLBody?
    public var files: SNLFiles?
    public var timeoutIntervalForRequest: Double?
    public var timeoutIntervalForResource: Double?

    public func execute(debug: Bool, _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws {
        awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        try provider.executeRequest(resource: resource, request: request, debug: debug, handler)
    }
    
    public func execute(_ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws {
        try execute(debug: false, handler)
    }

    public func execute<ResponseModel: Decodable & Sendable>(model: ResponseModel.Type,
                                                  debug: Bool,
                                                  _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void) throws
    {
        awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        try provider.executeRequest(resource: resource, request: request, debug: debug) { (data, response, error) in
            do {
                guard let data = data else {
                    try handler(nil, response, error)
                    return
                }
                let object = try JSONDecoder().decode(model, from: data)
                if let error {
                    try handler(object, response, SNLError(error))
                } else {
                    try handler(object, response, nil)
                }
            } catch let error {
                try? handler(nil, response, SNLError(error))
            }
        }
    }
    
    public func execute<ResponseModel: Decodable & Sendable>(model: ResponseModel.Type,
                                                  _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void) throws
    {
        try execute(model: model, debug: false, handler)
    }
    
    @discardableResult
    public func execute(debug: Bool) async throws -> (Data, URLResponse) {
        try await awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        return try await provider.executeRequest(resource: resource, request: request, debug: debug)
    }
    
    @discardableResult
    public func execute(debug: Bool) async throws -> Data {
        try await awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        return try await provider.executeRequest(resource: resource, request: request, debug: debug).0
    }
    
    @discardableResult
    public func execute() async throws -> (Data, URLResponse) {
        try await execute(debug: false)
    }
    
    @discardableResult
    public func execute() async throws -> Data {
        try await execute(debug: false).0
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> (ResponseModel, URLResponse) {
        try await awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        let out = try await provider.executeRequest(resource: resource, request: request, debug: debug)
        let data: Data = out.0
        do {
            let object = try JSONDecoder().decode(model, from: data)
            return (object, out.1)
        } catch {
            let dataString: String? = String(data: data, encoding: .utf8)
            throw SNLError("\(dataString ?? "") \(SNLError(error).description)")
        }
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> ResponseModel {
        try await execute(model: model, debug: debug).0
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> (ResponseModel, URLResponse) {
        try await execute(model: model, debug: false)
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> ResponseModel {
        try await execute(model: model, debug: false).0
    }

    public func waitExecute(debug: Bool, _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws {
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        try execute(debug: debug) { (data, response, error) in
            try handler(data, response, error)
            waitGroup.leave()
        }
        waitGroup.wait()
    }
    
    public func waitExecute(_ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws {
        try waitExecute(debug: false, handler)
    }

    public func waitExecute<ResponseModel: Decodable & Sendable>(model: ResponseModel.Type,
                                                      debug: Bool,
                                                      _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void) throws
    {
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        try execute(model: model, debug: debug) { (model, response, error) in
            try handler(model, response, error)
            waitGroup.leave()
        }
        waitGroup.wait()
    }
    
    public func waitExecute<ResponseModel: Decodable & Sendable>(model: ResponseModel.Type,
                                                      _ handler: @escaping @Sendable (ResponseModel?, URLResponse?, SNLError?) throws -> Void) throws
    {
        try waitExecute(model: model, debug: false, handler)
    }

    private func makeRequest() -> SNLRequestPrtcl {
        let mergedHeaders = mergeHeaders(resource.defaultHeaders, targetHeaders, requestHeaders)
        let mergedParams = mergeParams(resource.defaultParams.value, targetParams, requestParams)

        return SNLRequest(method: method,
                          path: path,
                          multipart: multipart,
                          dynamicPathsParts: dynamicPathsParts,
                          headers: mergedHeaders,
                          params: mergedParams,
                          hash: nil,
                          body: body,
                          files: files)
    }

    private func mergeHeaders(_ resourceHeaders: SNLHeader?, _ targetHeaders: SNLHeader?, _ requestHeaders: SNLHeader?) -> SNLHeader {
        var resultHeaders = mergeOptionalDictionary(resourceHeaders, targetHeaders)
        resultHeaders = mergeOptionalDictionary(resultHeaders, requestHeaders)
        return mergeOptionalDictionary(resultHeaders, defaultHeaders())
    }

    private func mergeParams(_ resourceParams: SNLParams?, _ targetParams: SNLParams?, _ requestParams: SNLParams?) -> SNLParams {
        let resultParams = mergeOptionalDictionary(resourceParams, targetParams)
        return mergeOptionalDictionary(resultParams, requestParams)
    }

    private func defaultHeaders() -> SNLHeader {
        var defaultHeaders: SNLHeader = [:]
        if body == nil && requestHeaders?[SNLHeaderName.contentType.description] == nil {
            defaultHeaders[SNLHeaderName.contentType.description] = SNLMIMEType.applicationXFormEncodedData.description
        }
        return defaultHeaders
    }
    
    private func awaitAvailableSlotForRequest() {
        guard let requestPerSecondOptions = resource.requestPerSecondOptions else { return }
        let delayBeforRetryRequest = requestPerSecondOptions.value.retryDelaySecond
        while !resource.allowRequest {
            Thread.sleep(forTimeInterval: TimeInterval(delayBeforRetryRequest) / 1_000_000_000)
        }
    }
    
    private func awaitAvailableSlotForRequest() async throws {
        guard let requestPerSecondOptions = resource.requestPerSecondOptions else { return }
        let delayBeforRetryRequest = requestPerSecondOptions.value.retryDelaySecond
        while !resource.allowRequest {
            try await Task.sleep(nanoseconds: UInt64(delayBeforRetryRequest))
        }
    }
}

