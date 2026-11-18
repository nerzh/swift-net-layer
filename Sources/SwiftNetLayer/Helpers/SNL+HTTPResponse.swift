import Foundation

public struct SNLHTTPResponse: Sendable {
    public let url: URL
    public let statusCode: Int
    public let headers: SNLHeader
    public let body: Data

    public init(url: URL, statusCode: Int, headers: SNLHeader = [:], body: Data) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}
