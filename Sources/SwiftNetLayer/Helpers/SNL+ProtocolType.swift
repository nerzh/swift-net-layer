//
//  SNL+ProtocolType.swift
//  
//
//  Created by Oleh Hudeichuk on 17.12.2019.
//

import Foundation

public enum SNLProtocolType: String, CustomStringConvertible, Sendable {
    case http
    case https

    public var description: String { self.rawValue }
}
