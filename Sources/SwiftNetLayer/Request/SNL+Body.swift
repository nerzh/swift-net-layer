import Foundation

public enum SNLBody {
    case raw(bytes: Data)
    case data(bytes: Data, contentType: SNLMIMEType)
    case json(any Encodable)
    case form([String: String])
    case multipart([SNLMultipartPart])

    public static func raw(bytes: Data?) -> SNLBody {
        .raw(bytes: bytes ?? Data())
    }

    public static func data(bytes: Data?, contentType: SNLMIMEType) -> SNLBody {
        .data(bytes: bytes ?? Data(), contentType: contentType)
    }

    public static func data(bytes: Data?, contentType: String) -> SNLBody {
        .data(bytes: bytes, contentType: .custom(contentType))
    }

    public static func data(_ string: String, contentType: SNLMIMEType) -> SNLBody {
        .data(bytes: Data(string.utf8), contentType: contentType)
    }

    public static func data(_ string: String, contentType: String) -> SNLBody {
        .data(string, contentType: .custom(contentType))
    }
}

public enum SNLMultipartPart {
    case field(name: String, value: String)
    case file(name: String, file: any SNLFilePrtcl)
}
