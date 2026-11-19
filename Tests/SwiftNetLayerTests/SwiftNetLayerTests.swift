import XCTest
import SwiftNetLayer
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SwiftNetLayerTests: XCTestCase, @unchecked Sendable {
    func testRepeatedSlashesAfterMissingDynamicSegmentAreNormalizedInRequests() async throws {
        let target = SNLTarget(
            resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test", version: "v1"),
            path: "/:id//users///:section?next=https://example.test/a//b#part//anchor"
        )
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .get,
            dynamicPathsParts: [":section": "a//b"]
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            let url = try XCTUnwrap(URLComponents(string: request.url))
            XCTAssertEqual(url.percentEncodedPath, "/v1/users/a%2F%2Fb")
            XCTAssertEqual(request.queryValues("next"), ["https://example.test/a//b"])
            XCTAssertEqual(url.fragment, "part//anchor")
        }
    }

    func testDynamicPathEncodingSurvivesAsyncAndCallbackRequests() async throws {
        let target = SNLTarget(
            resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test", version: "v1"),
            path: "/users/:id/extra/:optional?fixed=a%2Bb#section"
        )
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .get,
            dynamicPathsParts: [":id": "a/b?injected=1#part %"], requestParams: ["page": 2]
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            let url = try XCTUnwrap(URLComponents(string: request.url))
            XCTAssertEqual(url.percentEncodedPath, "/v1/users/a%2Fb%3Finjected%3D1%23part%20%25/extra")
            XCTAssertEqual(url.fragment, "section")
            XCTAssertEqual(request.queryValues("fixed"), ["a+b"])
            XCTAssertEqual(request.queryValues("page"), ["2"])
            XCTAssertTrue(request.queryValues("injected").isEmpty)
        }
    }

    func testQueryMergesWithExistingQueryAndPreservesFragment() async throws {
        let target = SNLTarget(
            resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test", version: "v1"),
            path: "/search?existing=a%2Bb&tag=base#section"
        )
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .get,
            requestParams: ["tag": "new", "q&=": "a+b &=%#?/", "filter": ["name": "Ada"]]
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            let url = try XCTUnwrap(URLComponents(string: request.url))
            XCTAssertEqual(url.path, "/v1/search")
            XCTAssertEqual(url.fragment, "section")
            XCTAssertEqual(request.queryValues("existing"), ["a+b"])
            XCTAssertEqual(request.queryValues("tag"), ["base", "new"])
            XCTAssertEqual(request.queryValues("q&="), ["a+b &=%#?/"])
            XCTAssertEqual(request.queryValues("filter[name]"), ["Ada"])
            XCTAssertTrue(request.body.isEmpty)
        }
    }

    func testParamsStayInURLForEveryMethodWithoutImplicitBody() async throws {
        let resource = SNLResource(
            provider: makeProvider(), domain: "swift-net-layer.test", defaultParams: ["locale": "en", "page": 1]
        )
        let target = SNLTarget(resource: resource, path: "/items", params: ["page": 2, "limit": 10])

        for method in [SNLHTTPMethod.get, .post, .put, .patch, .delete] {
            let executor = target.makeExecutor(
                target: target, resource: resource, method: method, requestParams: ["page": 3]
            )
            let request = try await capture(executor)
            XCTAssertEqual(request.method, method.description)
            XCTAssertEqual(request.queryValues("locale"), ["en"])
            XCTAssertEqual(request.queryValues("page"), ["3"])
            XCTAssertEqual(request.queryValues("limit"), ["10"])
            XCTAssertTrue(request.body.isEmpty)
            XCTAssertNil(request.contentType)
        }
    }

    func testTypedJSONIsSeparateFromQueryInAsyncAndCallbackRequests() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/items")
        let payload = Payload(name: "Ada & Grace", count: 2)
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .post,
            requestParams: ["page": 3], body: .json(payload)
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.queryValues("page"), ["3"])
            XCTAssertEqual(request.contentType, "application/json")
            XCTAssertEqual(try JSONDecoder().decode(Payload.self, from: request.body), payload)
            XCTAssertNil(URLComponents(string: request.url)?.queryItems?.first { $0.name == "name" })
        }
    }

    func testFormBodyUsesFormEncodingWithoutLeakingFieldsIntoURL() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/form?fixed=1")
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .post,
            requestParams: ["page": 2], body: .form(["secret": "a+b c&d", "a b": "=%"])
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.queryValues("fixed"), ["1"])
            XCTAssertEqual(request.queryValues("page"), ["2"])
            XCTAssertTrue(request.queryValues("secret").isEmpty)
            XCTAssertEqual(request.contentType, "application/x-www-form-urlencoded")
            XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "a+b=%3D%25&secret=a%2Bb+c%26d")
        }
    }

    func testMultipartUsesTypedFilesAndKeepsQuerySeparate() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/upload?fixed=1")
        let file: any SNLFilePrtcl = SNLFile(data: Data("file-bytes".utf8), fileName: "image.png", mimeType: SNLMIMEType.imagePNG.rawValue)
        let customFile = CustomFile(data: Data("custom-bytes".utf8), fileName: "custom.bin", mimeType: SNLMIMEType.custom("application/vnd.example").rawValue)
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .post,
            requestParams: ["page": 2],
            body: .multipart([
                .field(name: "folder", value: "avatars"),
                .file(name: "photo", file: file),
                .file(name: "custom", file: customFile)
            ])
        )

        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.queryValues("fixed"), ["1"])
            XCTAssertEqual(request.queryValues("page"), ["2"])
            XCTAssertTrue(request.queryValues("folder").isEmpty)
            let contentType = try XCTUnwrap(request.contentType)
            XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            let body = String(decoding: request.body, as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"folder\"\r\n\r\navatars\r\n"))
            XCTAssertTrue(body.contains("name=\"photo\"; filename=\"image.png\""))
            XCTAssertTrue(body.contains("Content-Type: image/png\r\n\r\nfile-bytes\r\n"))
            XCTAssertTrue(body.contains("name=\"custom\"; filename=\"custom.bin\""))
            XCTAssertTrue(body.contains("Content-Type: application/vnd.example\r\n\r\ncustom-bytes\r\n"))
            XCTAssertTrue(body.hasSuffix("--\(boundary)--"))
            XCTAssertFalse(body.contains("name=\"page\""))
        }
    }

    func testRawBodyPreservesBytesAndContentType() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/raw")
        let data = Data([0, 1, 128, 255])
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .put,
            body: .raw(data: data, contentType: SNLMIMEType.custom("application/vnd.example").rawValue)
        )
        let request = try await capture(executor)
        XCTAssertEqual(request.body, data)
        XCTAssertEqual(request.contentType, "application/vnd.example")
    }

    func testContentTypeAndHeaderOverridesArePreserved() async throws {
        let resource = SNLResource(
            provider: makeProvider(), domain: "swift-net-layer.test",
            defaultHeaders: [
                .contentType: "text/plain",
                .authorization: "Bearer AbCd",
                .custom("X-Level"): "resource",
                .custom("X-Target"): "resource",
                .custom("X-Resource"): "yes"
            ]
        )
        let target = SNLTarget(
            resource: resource, path: "/headers",
            headers: [
                .custom("content-TYPE"): "application/xml",
                .custom("x-level"): "target",
                .custom("x-target"): "target"
            ]
        )
        let executor = target.makeExecutor(
            target: target, resource: resource, method: .post,
            requestHeaders: [.contentType: "application/json", .custom("X-LEVEL"): "request"]
        )
        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.contentType, "application/json")
            XCTAssertEqual(request.headers["authorization"], "Bearer AbCd")
            XCTAssertEqual(request.headers["x-level"], "request")
            XCTAssertEqual(request.headers["x-target"], "target")
            XCTAssertEqual(request.headers["x-resource"], "yes")
            XCTAssertTrue(request.body.isEmpty)
        }
    }

    func testHeaderKeysMatchWithoutCaseSensitivity() {
        var headers: SNLHeader = [.contentType: "text/plain", .custom("X-Trace-ID"): "first"]
        headers[.custom("CONTENT-TYPE")] = "application/json"
        headers[.custom("x-trace-id")] = "second"

        XCTAssertEqual(headers.count, 2)
        XCTAssertEqual(headers[.contentType], "application/json")
        XCTAssertEqual(headers[.custom("content-type")], "application/json")
        XCTAssertEqual(headers[.custom("X-TRACE-ID")], "second")
        XCTAssertNil(headers[.accept])
        XCTAssertEqual(SNLHeaderName.authorization, .custom("AUTHORIZATION"))
        XCTAssertNotEqual(SNLHeaderName.authorization, .proxyAuthorization)
        XCTAssertEqual(SNLHeaderName.custom("X-Trace-ID").rawValue, "X-Trace-ID")
    }

    func testConflictingContentTypeFailsForAsyncAndCallbackRequests() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/conflict")
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .post,
            requestHeaders: [.contentType: "text/plain"], body: .json(Payload(name: "Ada", count: 1))
        )
        for callback in [false, true] {
            do {
                _ = try await capture(executor, callback: callback)
                XCTFail("Expected a conflicting Content-Type error")
            } catch {
                XCTAssertTrue(String(describing: error).contains("ConflictingContentType"))
            }
        }
    }

    func testTimeoutsReachRequestInAsyncAndCallbackExecutors() async throws {
        let resource = SNLResource(provider: TimeoutProvider(), domain: "swift-net-layer.test")
        let target = SNLTarget(resource: resource, path: "/timeouts")
        let executor = target.makeExecutor(
            target: target, resource: resource, method: .get,
            timeoutIntervalForRequest: 17, timeoutIntervalForResource: 23
        )
        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.headers["request-timeout"], "17.0")
            XCTAssertEqual(request.headers["resource-timeout"], "23.0")
        }
    }

    func testCustomProviderReturnsLibraryHTTPResponse() async throws {
        let resource = SNLResource(provider: TimeoutProvider(), domain: "swift-net-layer.test")
        let target = SNLTarget(resource: resource, path: "/custom-provider")
        let executor = target.makeExecutor(target: target, resource: resource, method: .get)

        let output = try await executor.execute(model: CapturedRequest.self)
        XCTAssertEqual(try JSONDecoder().decode(CapturedRequest.self, from: output.response.body).url, output.model.url)
        XCTAssertEqual(output.response.url, target.path)
        XCTAssertEqual(output.response.statusCode, 200)
        XCTAssertEqual(output.response.headers[.custom("x-provider")], "custom")

        let finished = expectation(description: "Custom provider HTTP response")
        executor.execute(model: CapturedRequest.self) { model, response, error in
            XCTAssertNotNil(model)
            XCTAssertFalse(response?.body.isEmpty ?? true)
            XCTAssertEqual(response?.url, output.response.url)
            XCTAssertEqual(response?.statusCode, 200)
            XCTAssertEqual(response?.headers[.custom("X-Provider")], "custom")
            XCTAssertNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testCustomProviderCanEncodeBodyWithoutNetTypes() async throws {
        let resource = SNLResource(provider: TimeoutProvider(), domain: "swift-net-layer.test")
        let target = SNLTarget(resource: resource, path: "/custom-provider")
        let payload = Payload(name: "Independent provider", count: 3)
        let executor = target.makeExecutor(
            target: target, resource: resource, method: .post,
            requestHeaders: [.custom("AUTHORIZATION"): "Bearer independent"], body: .json(payload)
        )
        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(try JSONDecoder().decode(Payload.self, from: request.body), payload)
            XCTAssertEqual(request.headers["authorization"], "Bearer independent")
        }
    }

    func testCustomTimeoutSessionCompletesAsyncAndCallbackRequests() async throws {
        let target = SNLTarget(resource: SNLResource(provider: makeProvider(), domain: "swift-net-layer.test"), path: "/timeouts")
        let executor = target.makeExecutor(
            target: target, resource: target.resource, method: .post,
            body: .json(Payload(name: "Ada", count: 1)), timeoutIntervalForRequest: 17
        )
        for callback in [false, true] {
            let request = try await capture(executor, callback: callback)
            XCTAssertEqual(request.contentType, "application/json")
            XCTAssertFalse(request.body.isEmpty)
        }
    }

    private func capture(_ executor: SNLExecutorPrtcl, callback: Bool = false) async throws -> CapturedRequest {
        if callback {
            return try await withCheckedThrowingContinuation { continuation in
                executor.execute(model: CapturedRequest.self) { request, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let request {
                        continuation.resume(returning: request)
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
            }
        }
        return try await executor.modelExecute(model: CapturedRequest.self)
    }
}

private struct Payload: Codable, Equatable {
    let name: String
    let count: Int
}

private struct CustomFile: SNLFilePrtcl {
    var data: Data
    var fileName: String
    var mimeType: String
}

private struct CapturedRequest: Codable, Sendable {
    let url: String
    let method: String
    let headers: [String: String]
    let body: Data

    var contentType: String? { headers["content-type"] }

    func queryValues(_ name: String) -> [String] {
        URLComponents(string: url)?.queryItems?.filter { $0.name == name }.compactMap(\.value) ?? []
    }
}

private final class EchoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "swift-net-layer.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let captured = CapturedRequest(
                url: request.url!.absoluteString,
                method: request.httpMethod!,
                headers: Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }),
                body: body
            )
            let data = try JSONEncoder().encode(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
extension EchoURLProtocol: @unchecked Sendable {}
#endif

private struct TimeoutProvider: SNLProviderPrtcl {
    let callbackContext: SNLCallbackContext = .unchecked

    init() {}

    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void
    ) {
        do {
            handler(try response(request), nil)
        } catch {
            handler(nil, SNLError(error))
        }
    }

    func executeRequest(resource: SNLResourcePrtcl, request: SNLRequestPrtcl, debug: Bool) async throws -> SNLHTTPResponse {
        try response(request)
    }

    private func response(_ request: SNLRequestPrtcl) throws -> SNLHTTPResponse {
        var body = Data()
        if case let .json(value) = request.body {
            body = try JSONEncoder().encode(value)
        }
        let captured = CapturedRequest(
            url: request.path.absoluteString, method: request.method.description,
            headers: [
                "request-timeout": request.timeoutIntervalForRequest.map(String.init(describing:)) ?? "nil",
                "resource-timeout": request.timeoutIntervalForResource.map(String.init(describing:)) ?? "nil",
                "authorization": request.headers?[.authorization] ?? "nil"
            ], body: body
        )
        return SNLHTTPResponse(
            url: request.path, statusCode: 200, headers: [.custom("X-Provider"): "custom"],
            body: try JSONEncoder().encode(captured)
        )
    }
}

private func makeProvider() -> SNLProvider {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EchoURLProtocol.self]
    return SNLProvider(session: URLSession(configuration: configuration))
}
