//
//  SNL+ProviderPrtcl.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
import SwiftExtensionsPack
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SNLProviderPrtcl: Sendable {
    
    init()
    
    func executeRequest(resource: SNLResourcePrtcl,
                        request: SNLRequestPrtcl,
                        debug: Bool,
                        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void) throws
    
    @discardableResult
    func executeRequest(resource: SNLResourcePrtcl,
                        request: SNLRequestPrtcl,
                        debug: Bool
    ) async throws -> (Data, URLResponse)
}


// MARK: Default Realisation NetProviderPrtcl

public extension SNLProviderPrtcl {
    
    private func fullURL(_ resource: SNLResourcePrtcl, _ request: SNLRequestPrtcl) -> URL {
        var path = request.path.absoluteString
        if !path["^\\/"] { path = "/\(path)" }
        guard let newURL = URL(string: "\(resource.url.absoluteString)\(path)") else {
            fatalError("NetProvider: Bad new URL")
        }
        
        return newURL
    }
    
    func executeRequest(resource: SNLResourcePrtcl,
                        request: SNLRequestPrtcl,
                        debug: Bool = false,
                        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void = {_, _, _ in}) throws -> Void
    {
        var newParams = request.params ?? [:]
        for (paramName, file) in request.files ?? [:] {
            newParams[paramName] = NetSessionFile(data: file.data, fileName: file.fileName, mimeType: file.mimeType)
        }
        newParams = changeToSessionFiles(newParams)
        
        var sharedSession: URLSession!
        if request.timeoutIntervalForRequest != nil || request.timeoutIntervalForResource != nil {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
            sessionConfiguration.urlCache = nil
            sessionConfiguration.timeoutIntervalForRequest = request.timeoutIntervalForRequest ?? 1000
            sessionConfiguration.timeoutIntervalForResource = request.timeoutIntervalForResource ?? 0
            sharedSession = URLSession(configuration: sessionConfiguration)
        }
        let callback = { @Sendable (data: Data?, urlResponse: URLResponse?, error: Error?) -> Void in
            if let error {
                try handler(data, urlResponse, SNLError(String(describing: error)))
            } else {
                try handler(data, urlResponse, nil)
            }
        }
        
        if debug {
            printDebugInfo(resource: resource, request: request, params: newParams)
        }
        
        try Net.sendRequest(url: fullURL(resource, request).absoluteString,
                            method: request.method.rawValue.uppercased(),
                            headers: request.headers,
                            params: newParams,
                            body: request.body,
                            multipart: request.multipart,
                            session: sharedSession ?? nil,
                            callback)
    }
    
    @discardableResult
    func executeRequest(resource: SNLResourcePrtcl,
                        request: SNLRequestPrtcl,
                        debug: Bool = false
    ) async throws -> (Data, URLResponse) {
        var newParams = request.params ?? [:]
        for (paramName, file) in request.files ?? [:] {
            newParams[paramName] = NetSessionFile(data: file.data, fileName: file.fileName, mimeType: file.mimeType)
        }
        newParams = changeToSessionFiles(newParams)
        
        var sharedSession: URLSession!
        if request.timeoutIntervalForRequest != nil || request.timeoutIntervalForResource != nil {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
            sessionConfiguration.urlCache = nil
            sessionConfiguration.timeoutIntervalForRequest = request.timeoutIntervalForRequest ?? 1000
            sessionConfiguration.timeoutIntervalForResource = request.timeoutIntervalForResource ?? 0
            sharedSession = URLSession(configuration: sessionConfiguration)
        }
        
        if debug {
            printDebugInfo(resource: resource, request: request, params: newParams)
        }
        
        return try await Net.sendRequest(url: fullURL(resource, request).absoluteString,
                                         method: request.method.rawValue.uppercased(),
                                         headers: request.headers,
                                         params: newParams,
                                         body: request.body,
                                         multipart: request.multipart,
                                         session: sharedSession ?? nil)
    }
    
    private func changeToSessionFiles<T>(_ anyObject: T) -> T {
        func checkValue(_ anyObject: Any) -> Any {
            if var array = anyObject as? Array<Any> {
                for (index, element) in array.enumerated() {
                    array[index] = checkValue(element)
                }
                return array
            } else if var dictionary = anyObject as? Dictionary<String, Any> {
                for key in dictionary.keys {
                    dictionary[key] = checkValue(dictionary[key]!)
                }
                return dictionary
            } else {
                #warning("TODO: STUPID FIX. CAST __SwiftValue to SNLFilePrtcl Protocol for iOS 13 RETURN NIL")
                if let element = anyObject as? SNLFile {
                    return NetSessionFile(data: element.data, fileName: element.fileName, mimeType: element.mimeType)
                } else {
                    return anyObject
                }
            }
        }
        
        return checkValue(anyObject as AnyObject) as! T
    }
    
    private func printDebugInfo(resource: SNLResourcePrtcl, request: SNLRequestPrtcl, params: [String: Any]) {
        print("SWIFT-NET-LAYER: url \(fullURL(resource, request).absoluteString)")
        print("SWIFT-NET-LAYER: method \(request.method.rawValue.uppercased())")
        print("SWIFT-NET-LAYER: headers \(request.headers ?? [:])")
        print("SWIFT-NET-LAYER: params \(params)")
        print("SWIFT-NET-LAYER: body \(request.body?.toJson ?? "")")
        print("SWIFT-NET-LAYER: multipart \(request.multipart)")
    }
}
