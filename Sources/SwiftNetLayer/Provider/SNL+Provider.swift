//
//  File.swift
//
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
import SwiftExtensionsPack
import SwiftRegularExpression
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class SNLProvider: SNLProviderPrtcl {
    private let session: URLSession

    public init() {
        session = Net.sharedSession
    }

    public init(session: URLSession) {
        self.session = session
    }

    public var callbackContext: SNLCallbackContext { .operationQueue(session.delegateQueue) }

    private func fullURL(_ resource: SNLResourcePrtcl, _ request: SNLRequestPrtcl) -> URL {
        var path = request.path.absoluteString
        if !path["^\\/"] { path = "/\(path)" }
        guard let newURL = URL(string: "\(resource.url.absoluteString)\(path)") else {
            fatalError("NetProvider: Bad new URL")
        }

        return newURL
    }

    public func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void = { _, _ in }
    ) {
        let session = reconfigureSession(request)
        defer { session?.finishTasksAndInvalidate() }

        let safeRequest = SafeValue(request)

        let completion: @Sendable (Data?, URLResponse?, Error?) -> Void = { data, urlResponse, error in
            if
                debug,
                let data, let urlResponse
            {
                self.printDebugInfo(
                    resource: resource,
                    request: safeRequest.value,
                    response: (data: data, response: urlResponse)
                )
            }
            if let error {
                handler(nil, SNLError(error))
                return
            }

            let response: SNLHTTPResponse
            do {
                response = try self.makeHTTPResponse(data: data, response: urlResponse)
            } catch {
                handler(nil, SNLError(error))
                return
            }

            handler(response, nil)
        }

        let activeSession = session ?? self.session
        do {
            switch try prepareRequest(resource, request) {
            case let .raw(urlRequest):
                activeSession.dataTask(with: urlRequest, completionHandler: completion).resume()
            case let .encoded(url, method, headers, params, body):
                Net.sendRequest(url: url, method: method, headers: headers, queryParams: params,
                                body: body, session: activeSession, completion)
            }
        } catch {
            handler(nil, SNLError(error))
        }
    }

    @discardableResult
    public func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false
    ) async throws -> SNLHTTPResponse {
        let session = reconfigureSession(request)
        defer { session?.finishTasksAndInvalidate() }

        let activeSession = session ?? self.session
        let response: (data: Data, response: URLResponse)
        switch try prepareRequest(resource, request) {
        case let .raw(urlRequest):
            try Task.checkCancellation()
            response = try await activeSession.data(for: urlRequest)
        case let .encoded(url, method, headers, params, body):
            response = try await Net.sendRequest(url: url, method: method, headers: headers, queryParams: params,
                                                 body: body, session: activeSession)
        }

        if debug {
            printDebugInfo(resource: resource, request: request, response: response)
        }

        return try makeHTTPResponse(data: response.data, response: response.response)
    }

    private func makeHTTPResponse(data: Data?, response: URLResponse?) throws -> SNLHTTPResponse {
        guard let response = response as? HTTPURLResponse,
              let url = response.url else {
            throw SNLError("Expected an HTTP response with a URL")
        }
        guard let data else {
            throw SNLError("Missing HTTP response body")
        }

        var headers: SNLHeader = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String else { continue }
            headers[.custom(name)] = String(describing: value)
        }

        return SNLHTTPResponse(url: url, statusCode: response.statusCode, headers: headers, body: data)
    }

    private func makeNetHeaders(_ headers: SNLHeader?) -> [String: String]? {
        guard let headers else { return nil }
        return Dictionary(uniqueKeysWithValues: headers.map { ($0.key.rawValue, $0.value) })
    }

    private enum PreparedRequest {
        case raw(URLRequest)
        case encoded(url: String, method: String, headers: [String: String]?, params: [String: Any]?, body: NetBody?)
    }

    private func prepareRequest(_ resource: SNLResourcePrtcl, _ request: SNLRequestPrtcl) throws -> PreparedRequest {
        let url = fullURL(resource, request)
        let method = request.method.description
        let headers = makeNetHeaders(request.headers)
        let body: NetBody?
        switch request.body {
        case nil:
            body = nil
        case let .raw(bytes):
            guard let contentType = request.headers?[.contentType] else {
                // NetBody.raw always supplies a MIME type. Leave the header to URLSession here.
                var urlRequest = URLRequest(url: try appendingQueryParams(request.params, to: url))
                urlRequest.httpMethod = method
                urlRequest.allHTTPHeaderFields = headers
                urlRequest.httpBody = bytes
                return .raw(urlRequest)
            }
            body = .raw(data: bytes, contentType: .custom(contentType))
        case let .data(bytes, contentType):
            body = .raw(data: bytes, contentType: .custom(contentType.rawValue))
        case let .json(value):
            body = .json(value)
        case let .form(fields):
            body = .form(fields)
        case let .multipart(parts):
            body = .multipart(parts.map { part in
                switch part {
                case let .field(name, value):
                    return .field(name: name, value: value)
                case let .file(name, file):
                    return .file(name: name, file: NetSessionFile(
                        data: file.data, fileName: file.fileName, mimeType: .custom(file.mimeType)
                    ))
                }
            })
        }
        return .encoded(url: url.absoluteString, method: method, headers: headers, params: request.params, body: body)
    }

    private func appendingQueryParams(_ params: SNLParams?, to url: URL) throws -> URL {
        let query = Net.paramsString(params)
        guard !query.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Net.NetErrors.NotValidParams
        }
        let existing = components.percentEncodedQuery ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("&") ? "" : "&"
        components.percentEncodedQuery = existing + separator + query
        guard let result = components.url else { throw Net.NetErrors.NotValidParams }
        return result
    }

    private func reconfigureSession(_ request: SNLRequestPrtcl) -> URLSession? {
        guard request.timeoutIntervalForRequest != nil || request.timeoutIntervalForResource != nil else {
            return nil
        }
        let configuration = session.configuration.copy() as! URLSessionConfiguration
        if let timeout = request.timeoutIntervalForRequest {
            configuration.timeoutIntervalForRequest = timeout
        }
        if let timeout = request.timeoutIntervalForResource {
            configuration.timeoutIntervalForResource = timeout
        }
        return URLSession(
            configuration: configuration,
            delegate: session.delegate,
            delegateQueue: session.delegateQueue
        )
    }

    private func printDebugInfo(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        response: (data: Data, response: URLResponse)
    ) {
        print("SWIFT-NET-LAYER: Request")
        print("SWIFT-NET-LAYER: url \(fullURL(resource, request).absoluteString)")
        print("SWIFT-NET-LAYER: method \(request.method.rawValue.uppercased())")
        print("SWIFT-NET-LAYER: headers \(request.headers ?? [:])")
        print("SWIFT-NET-LAYER: queryParams \(request.params ?? [:])")
        print("SWIFT-NET-LAYER: body \(String(describing: request.body))")
        print("SWIFT-NET-LAYER: Response")
        print("SWIFT-NET-LAYER: body \(String(describing: String(data: response.data, encoding: .utf8)))")
        print("SWIFT-NET-LAYER: URLResponse \(response.response.debugDescription)")
    }
}
