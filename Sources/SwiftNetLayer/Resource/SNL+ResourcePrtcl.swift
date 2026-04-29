//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation
import SwiftExtensionsPack

public protocol SNLResourcePrtcl: Sendable {

    var provider: SNLProviderPrtcl { get }
    var `protocol`: SNLProtocolType { get }
    var domain: String { get }
    var version: String? { get }
    var defaultHeaders: [String: String]? { get }
    var defaultParams: SafeValue<[String: Any]?> { get }
    var url: URL { get }
    var requestPerSecondOptions: SafeValue<RequestPerSecondOptions>? { get }
    var allowRequest: Bool { get }
}

public extension SNLResourcePrtcl {

    var url: URL {
        let version = self.version != nil ? "/\(self.version!)" : ""
        guard let url = URL(string: "\(`protocol`)://\(domain)\(version)") else { fatalError("NetResource: Bad URL") }
        return url
    }
}

