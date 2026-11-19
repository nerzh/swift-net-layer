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

        Net.sendRequest(url: fullURL(resource, request).absoluteString,
                            method: request.method.rawValue.uppercased(),
                            headers: makeNetHeaders(request.headers),
                            queryParams: request.params,
                            body: makeNetBody(request.body),
                            session: session ?? self.session
        ) { (data: Data?, urlResponse: URLResponse?, error: Error?) in
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
    }

    @discardableResult
    public func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false
    ) async throws -> SNLHTTPResponse {
        let session = reconfigureSession(request)
        defer { session?.finishTasksAndInvalidate() }

        let response = try await Net.sendRequest(url: fullURL(resource, request).absoluteString,
                                                 method: request.method.rawValue.uppercased(),
                                                 headers: makeNetHeaders(request.headers),
                                                 queryParams: request.params,
                                                 body: makeNetBody(request.body),
                                                 session: session ?? self.session)

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

    private func makeNetBody(_ body: SNLBody?) -> NetBody? {
        guard let body else { return nil }
        switch body {
        case let .raw(data, contentType):
            return .raw(data: data, contentType: .custom(contentType))
        case let .json(value):
            return .json(value)
        case let .form(fields):
            return .form(fields)
        case let .multipart(parts):
            return .multipart(parts.map { part in
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
