import Foundation

public enum SNLBody {
    case raw(data: Data, contentType: String = SNLMIMEType.applicationOctetStream.rawValue)
    case json(any Encodable)
    case form([String: String])
    case multipart([SNLMultipartPart])

    public static func raw(_ string: String, contentType: String = SNLMIMEType.applicationOctetStream.rawValue) -> SNLBody {
        .raw(data: Data(string.utf8), contentType: contentType)
    }
}

public enum SNLMultipartPart {
    case field(name: String, value: String)
    case file(name: String, file: any SNLFilePrtcl)
}
