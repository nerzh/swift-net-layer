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
        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void = {_, _, _ in}
    ) throws -> Void {
        let session = makeSession(request)
        defer { session?.finishTasksAndInvalidate() }

        let safeRequest = SafeValue(request)

        try Net.sendRequest(url: fullURL(resource, request).absoluteString,
                            method: request.method.rawValue.uppercased(),
                            headers: request.headers,
                            queryParams: request.params,
                            body: makeNetBody(request.body),
                            session: session ?? self.session,
                            beforeResume: nil,
                            afterResume: nil
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
                try handler(data, urlResponse, SNLError(error))
            } else {
                try handler(data, urlResponse, nil)
            }
        }
    }

    @discardableResult
    public func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool = false
    ) async throws -> (Data, URLResponse) {
        let session = makeSession(request)
        defer { session?.finishTasksAndInvalidate() }

        let response = try await Net.sendRequest(url: fullURL(resource, request).absoluteString,
                                                 method: request.method.rawValue.uppercased(),
                                                 headers: request.headers,
                                                 queryParams: request.params,
                                                 body: makeNetBody(request.body),
                                                 session: session ?? self.session)

        if debug {
            printDebugInfo(resource: resource, request: request, response: response)
        }

        return response
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

    private func makeSession(_ request: SNLRequestPrtcl) -> URLSession? {
        guard request.timeoutIntervalForRequest != nil || request.timeoutIntervalForResource != nil else {
            return nil
        }
        let configuration = session.configuration
        if let timeout = request.timeoutIntervalForRequest {
            configuration.timeoutIntervalForRequest = timeout
        }
        if let timeout = request.timeoutIntervalForResource {
            configuration.timeoutIntervalForResource = timeout
        }
        return URLSession(configuration: configuration)
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
