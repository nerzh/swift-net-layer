//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 27.01.2020.
//

import Foundation

public enum SNLHeaderName: Hashable, Sendable, CustomStringConvertible {
    case aIM
    case accept
    case acceptCharset
    case acceptEncoding
    case acceptLanguage
    case acceptDatetime
    case accessControlRequestMethod
    case accessControlRequestHeaders
    case authorization
    case cacheControl
    case connection
    case contentLength
    case contentType
    case cookie
    case date
    case expect
    case forwarded
    case from
    case host
    case ifMatch
    case ifModifiedSince
    case ifNoneMatch
    case ifRange
    case mfUnmodifiedSince
    case maxForwards
    case origin
    case pragma
    case proxyAuthorization
    case range
    case referer
    case tE
    case userAgent
    case upgrade
    case via
    case warning

    case custom(String)

    public var rawValue: String {
        switch self {
        case .aIM: return "A-IM"
        case .accept: return "Accept"
        case .acceptCharset: return "Accept-Charset"
        case .acceptEncoding: return "Accept-Encoding"
        case .acceptLanguage: return "Accept-Language"
        case .acceptDatetime: return "Accept-Datetime"
        case .accessControlRequestMethod: return "Access-Control-Request-Method"
        case .accessControlRequestHeaders: return "Access-Control-Request-Headers"
        case .authorization: return "Authorization"
        case .cacheControl: return "Cache-Control"
        case .connection: return "Connection"
        case .contentLength: return "Content-Length"
        case .contentType: return "Content-Type"
        case .cookie: return "Cookie"
        case .date: return "Date"
        case .expect: return "Expect"
        case .forwarded: return "Forwarded"
        case .from: return "From"
        case .host: return "Host"
        case .ifMatch: return "If-Match"
        case .ifModifiedSince: return "If-Modified-Since"
        case .ifNoneMatch: return "If-None-Match"
        case .ifRange: return "If-Range"
        case .mfUnmodifiedSince: return "If-Unmodified-Since"
        case .maxForwards: return "Max-Forwards"
        case .origin: return "Origin"
        case .pragma: return "Pragma"
        case .proxyAuthorization: return "Proxy-Authorization"
        case .range: return "Range"
        case .referer: return "Referer"
        case .tE: return "TE"
        case .userAgent: return "User-Agent"
        case .upgrade: return "Upgrade"
        case .via: return "Via"
        case .warning: return "Warning"
        case let .custom(value): return value
        }
    }

    public var description: String { self.rawValue }
}
