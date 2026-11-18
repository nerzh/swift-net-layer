//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
import SwiftExtensionsPack

public struct SNLRequest: SNLRequestPrtcl {
    
    public var method: SNLHTTPMethod
    public var headers: SNLHeader?
    public var params: [String: Any]?
    public var hash: String?
    public var body: SNLBody?
    public var timeoutIntervalForRequest: Double?
    public var timeoutIntervalForResource: Double?

    private var pathTemplate: URL
    public var path: URL {
        set { pathTemplate = newValue }
        get { urlWithDynamicPath(path: pathTemplate) }
    }

    public var dynamicPathsParts: [String: String]

    public init(
        method: SNLHTTPMethod,
        path: URL,
        dynamicPathsParts: [String: String]?,
        headers: SNLHeader? = nil,
        params: [String: Any]? = nil,
        hash: String? = nil,
        body: SNLBody? = nil,
        timeoutIntervalForRequest: Double? = nil,
        timeoutIntervalForResource: Double? = nil
    ) {
        self.method = method
        self.dynamicPathsParts = dynamicPathsParts ?? [:]
        self.headers = headers
        self.params = params
        self.hash = hash
        self.body = body
        self.pathTemplate = path
        self.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.timeoutIntervalForResource = timeoutIntervalForResource
    }

    private func urlWithDynamicPath(path: URL) -> URL {
        return replacePathsPart(path: path.absoluteString, parts: dynamicPathsParts)
    }

    private func replacePathsPart(path: String, parts: [String: String]) -> URL {
        guard var components = URLComponents(string: path) else { fatalError("NetRequest: Bad PATH") }
        let pathParts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard pathParts.contains(where: { $0.hasPrefix(":") }) else {
            guard let url = URL(string: path) else { fatalError("NetRequest: Bad PATH") }
            return url
        }

        let resolvedParts = pathParts.compactMap { part -> String? in
            guard part.hasPrefix(":") else { return String(part) }
            let key = String(part).removingPercentEncoding ?? String(part)
            guard let value = parts[key], !value.isEmpty else { return nil }

            let encodedValue = Net.urlEncode(value)
            if encodedValue == "." || encodedValue == ".." {
                return encodedValue.replacingOccurrences(of: ".", with: "%2E")
            }
            return encodedValue
        }
        var resolvedPath = resolvedParts.joined(separator: "/")
        if resolvedPath.isEmpty && components.percentEncodedPath.hasPrefix("/") {
            resolvedPath = "/"
        }
        components.percentEncodedPath = resolvedPath

        guard let url = components.url else { fatalError("NetRequest: Bad PATH") }

        return url
    }
}
