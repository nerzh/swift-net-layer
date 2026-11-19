//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 19.12.2019.
//

import Dispatch
import Foundation
import SwiftExtensionsPack

public struct SNLExecutor: SNLExecutorPrtcl {
    public var resource: SNLResourcePrtcl
    public var method: SNLHTTPMethod
    public var path: URL
    public var dynamicPathsParts: SNLDynamicParts?
    public var targetHeaders: SNLHeader?
    public var targetParams: SNLParams?
    public var requestHeaders: SNLHeader?
    public var requestParams: SNLParams?
    public var body: SNLBody?
    public var timeoutIntervalForRequest: Double?
    public var timeoutIntervalForResource: Double?

    public func execute(debug: Bool, _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void) {
        awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        provider.executeRequest(resource: resource, request: request, debug: debug, handler)
    }
    
    public func execute(_ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void) {
        execute(debug: false, handler)
    }
    
    public func execute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    ) {
        awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        provider.executeRequest(resource: resource, request: request, debug: debug) { (response, error) in
            if let error {
                handler(nil, response, error)
                return
            }

            guard let response else {
                handler(nil, nil, SNLError("Missing HTTP response"))
                return
            }

            let object: ResponseModel
            do {
                object = try JSONDecoder().decode(model, from: response.body)
            } catch {
                handler(nil, response, SNLError(error))
                return
            }

            handler(object, response, error)
        }
    }
    
    public func execute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    ) {
        execute(model: model, debug: false, handler)
    }
    
    @discardableResult
    public func execute(debug: Bool) async throws -> SNLHTTPResponse {
        try await awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        return try await provider.executeRequest(resource: resource, request: request, debug: debug)
    }
    
    @discardableResult
    public func execute() async throws -> SNLHTTPResponse {
        try await execute(debug: false)
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> (model: ResponseModel, response: SNLHTTPResponse) {
        try await awaitAvailableSlotForRequest()
        let provider = resource.provider
        let request = makeRequest()
        let out = try await provider.executeRequest(resource: resource, request: request, debug: debug)
        let data = out.body
        do {
            let object = try JSONDecoder().decode(model, from: data)
            return (model: object, response: out)
        } catch {
            let dataString: String? = String(data: data, encoding: .utf8)
            throw SNLError("\(dataString ?? "") \(SNLError(error).description)")
        }
    }
    
    @discardableResult
    public func modelExecute<ResponseModel: Decodable>(model: ResponseModel.Type, debug: Bool) async throws -> ResponseModel {
        try await execute(model: model, debug: debug).model
    }
    
    @discardableResult
    public func execute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> (model: ResponseModel, response: SNLHTTPResponse) {
        try await execute(model: model, debug: false)
    }
    
    @discardableResult
    public func modelExecute<ResponseModel: Decodable>(model: ResponseModel.Type) async throws -> ResponseModel {
        try await modelExecute(model: model, debug: false)
    }

    public func waitExecute(debug: Bool, _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void) {
        if let error = waitExecutionError {
            handler(nil, error)
            return
        }
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        execute(debug: debug) { response, error in
            defer { waitGroup.leave() }
            handler(response, error)
        }
        waitGroup.wait()
    }
    
    public func waitExecute(_ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void) {
        waitExecute(debug: false, handler)
    }
    
    public func waitExecute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        debug: Bool,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    ) {
        if let error = waitExecutionError {
            handler(nil, nil, error)
            return
        }
        let waitGroup = DispatchGroup()
        waitGroup.enter()
        execute(model: model, debug: debug) { model, response, error in
            defer { waitGroup.leave() }
            handler(model, response, error)
        }
        waitGroup.wait()
    }
    
    public func waitExecute<ResponseModel: Decodable & Sendable>(
        model: ResponseModel.Type,
        _ handler: @escaping @Sendable (ResponseModel?, SNLHTTPResponse?, SNLError?) -> Void
    ) {
        waitExecute(model: model, debug: false, handler)
    }

    private var waitExecutionError: SNLError? {
        switch resource.provider.callbackContext {
        case .waitUnsupported:
            return SNLError("This provider does not support waitExecute; use execute instead")
        case .unchecked:
            return nil
        case let .dispatchQueue(queue):
            guard isExecuting(on: queue) else { return nil }
        case let .operationQueue(queue):
            guard isExecuting(on: queue) else { return nil }
        }
        return SNLError("waitExecute cannot block the provider callback queue; use execute instead")
    }

    private func isExecuting(on operationQueue: OperationQueue) -> Bool {
        if OperationQueue.current === operationQueue {
            return true
        }
        let isMainQueue = operationQueue === OperationQueue.main
        if isMainQueue && Thread.isMainThread {
            return true
        }
        guard let queue = isMainQueue ? DispatchQueue.main : operationQueue.underlyingQueue else {
            return false
        }
        return isExecuting(on: queue)
    }

    private func isExecuting(on queue: DispatchQueue) -> Bool {
        let key = DispatchSpecificKey<Bool>()
        queue.setSpecific(key: key, value: true)
        defer { queue.setSpecific(key: key, value: nil) }
        return DispatchQueue.getSpecific(key: key) == true ||
            (Thread.isMainThread && DispatchQueue.main.getSpecific(key: key) == true)
    }

    private func makeRequest() -> SNLRequestPrtcl {
        let mergedHeaders = mergeHeaders(resource.defaultHeaders, targetHeaders, requestHeaders)
        let mergedParams = mergeParams(resource.defaultParams.value, targetParams, requestParams)

        return SNLRequest(method: method,
                          path: path,
                          dynamicPathsParts: dynamicPathsParts,
                          headers: mergedHeaders,
                          params: mergedParams,
                          hash: nil,
                          body: body,
                          timeoutIntervalForRequest: timeoutIntervalForRequest,
                          timeoutIntervalForResource: timeoutIntervalForResource)
    }

    private func mergeHeaders(_ resourceHeaders: SNLHeader?, _ targetHeaders: SNLHeader?, _ requestHeaders: SNLHeader?) -> SNLHeader {
        var resultHeaders = mergeOptionalDictionary(resourceHeaders, targetHeaders)
        resultHeaders = mergeOptionalDictionary(resultHeaders, requestHeaders)
        return resultHeaders
    }

    private func mergeParams(_ resourceParams: SNLParams?, _ targetParams: SNLParams?, _ requestParams: SNLParams?) -> SNLParams {
        let resultParams = mergeOptionalDictionary(resourceParams, targetParams)
        return mergeOptionalDictionary(resultParams, requestParams)
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

