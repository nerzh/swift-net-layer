import Foundation
import SwiftExtensionsPack
import SwiftNetLayer
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class HTTPStatusTests: XCTestCase, @unchecked Sendable {
    func testAsyncRawExecutorsReturnNonSuccessStatuses() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }

        for statusCode in [300, 400, 401, 404, 429, 500, 503] {
            let executor = makeHTTPStatusExecutor(session: session, path: "/\(statusCode)")
            let output: SNLHTTPResponse = try await executor.execute()
            XCTAssertEqual(output.body, httpStatusValidBody)
            XCTAssertEqual(output.statusCode, statusCode)
        }
    }

    func testAsyncModelExecutorsDecodeNonSuccessStatuses() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/500")

        let model = try await executor.modelExecute(model: HTTPStatusPayload.self, debug: false)
        XCTAssertEqual(model.value, 42)
        let output = try await executor.execute(model: HTTPStatusPayload.self, debug: false)
        XCTAssertEqual(output.model.value, 42)
        XCTAssertEqual(output.response.body, httpStatusValidBody)
        XCTAssertEqual(output.response.statusCode, 500)
    }

    func testInvalidJSONIsReturnedRawAndFailsOnlyWhenDecoding() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/500/invalid")

        let output: SNLHTTPResponse = try await executor.execute()
        XCTAssertEqual(output.body, httpStatusInvalidBody)
        XCTAssertEqual(output.statusCode, 500)

        do {
            let _: HTTPStatusPayload = try await executor.modelExecute(model: HTTPStatusPayload.self)
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertNotNil(error as? SNLError)
        }
    }

    func testRawCallbacksReturnNonSuccessResponsesAndBody() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }

        for statusCode in [300, 400, 401, 404, 429, 500, 503] {
            let finished = expectation(description: "Non-success HTTP response callback")
            finished.assertForOverFulfill = true
            let calls = SafeValue(0)
            let executor = makeHTTPStatusExecutor(session: session, path: "/\(statusCode)")

            executor.execute { response, error in
                calls.change { $0 += 1 }
                XCTAssertEqual(response?.body, httpStatusValidBody)
                XCTAssertEqual(response?.statusCode, statusCode)
                XCTAssertNil(error)
                finished.fulfill()
            }

            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testModelCallbacksPreserveResponseWhenDecodingFails() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }

        for invalidJSON in [false, true] {
            let finished = expectation(description: "Model callback for a non-success status")
            finished.assertForOverFulfill = true
            let calls = SafeValue(0)
            let path = invalidJSON ? "/500/invalid" : "/500"
            let executor = makeHTTPStatusExecutor(session: session, path: path)

            executor.execute(model: HTTPStatusPayload.self) { model, response, error in
                calls.change { $0 += 1 }
                XCTAssertEqual(response?.statusCode, 500)
                XCTAssertEqual(response?.body, invalidJSON ? httpStatusInvalidBody : httpStatusValidBody)
                if invalidJSON {
                    XCTAssertNil(model)
                    XCTAssertNotNil(error)
                } else {
                    XCTAssertEqual(model?.value, 42)
                    XCTAssertNil(error)
                }
                finished.fulfill()
            }

            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testSuccessfulStatusesReturnDataIncludingEmpty204Response() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }

        for statusCode in [200, 201, 204, 206, 299] {
            let body = statusCode == 204 ? Data() : httpStatusValidBody
            let executor = makeHTTPStatusExecutor(session: session, path: "/\(statusCode)")
            let output: SNLHTTPResponse = try await executor.execute()
            XCTAssertEqual(output.body, body)
            XCTAssertEqual(output.statusCode, statusCode)

            let finished = expectation(description: "Successful raw callback")
            executor.execute { response, error in
                XCTAssertEqual(response?.body, body)
                XCTAssertEqual(response?.statusCode, statusCode)
                XCTAssertNil(error)
                finished.fulfill()
            }
            await fulfillment(of: [finished], timeout: 2)
        }
    }

    func testSuccessfulStatusStillDecodesModels() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/201")

        let model = try await executor.modelExecute(model: HTTPStatusPayload.self)
        XCTAssertEqual(model.value, 42)
        let output = try await executor.execute(model: HTTPStatusPayload.self)
        XCTAssertEqual(output.model.value, 42)
        XCTAssertEqual(output.response.body, httpStatusValidBody)
        XCTAssertEqual(output.response.statusCode, 201)

        let finished = expectation(description: "Successful model callback")
        executor.execute(model: HTTPStatusPayload.self) { model, response, error in
            XCTAssertEqual(model?.value, 42)
            XCTAssertEqual(response?.statusCode, 201)
            XCTAssertNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testRequestPreparationErrorsReachCallbacksOnce() async {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let resource = SNLResource(provider: SNLProvider(session: session), domain: "swift-net-layer.test")
        let target = SNLTarget(resource: resource, path: "/200")
        let executor = target.makeExecutor(
            target: target, resource: resource, method: .post,
            requestHeaders: [.contentType: "text/plain"], body: .json(["value": 42])
        )

        for useModel in [false, true] {
            let finished = expectation(description: "Request preparation error callback")
            finished.assertForOverFulfill = true
            let calls = SafeValue(0)

            if useModel {
                executor.execute(model: HTTPStatusPayload.self) { model, response, error in
                    calls.change { $0 += 1 }
                    XCTAssertNil(model)
                    XCTAssertNil(response)
                    XCTAssertTrue(error?.reason.contains("ConflictingContentType") == true)
                    finished.fulfill()
                }
            } else {
                executor.execute { response, error in
                    calls.change { $0 += 1 }
                    XCTAssertNil(response)
                    XCTAssertTrue(error?.reason.contains("ConflictingContentType") == true)
                    finished.fulfill()
                }
            }

            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testTransportErrorsRemainErrors() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/transport-error")

        do {
            let _: SNLHTTPResponse = try await executor.execute()
            XCTFail("Expected a transport error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        let finished = expectation(description: "Transport error callback")
        executor.execute { response, error in
            XCTAssertNil(response)
            XCTAssertNotNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testNonHTTPResponsesFailAsyncAndCallbackRequests() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/non-http")

        do {
            let _: SNLHTTPResponse = try await executor.execute()
            XCTFail("Expected an unsupported response error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Expected an HTTP response"))
        }

        let finished = expectation(description: "Unsupported response callback")
        executor.execute { response, error in
            XCTAssertNil(response)
            XCTAssertTrue(error?.reason.contains("Expected an HTTP response") == true)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }

    func testProviderPreservesResponseURLAndTypedHeaders() async throws {
        let session = makeHTTPStatusSession()
        defer { session.invalidateAndCancel() }
        let executor = makeHTTPStatusExecutor(session: session, path: "/final-response")
        let finalURL = URL(string: "https://swift-net-layer.test/final")!
        let cookie = "session=abc; Expires=Wed, 21 Oct 2030 07:28:00 GMT; Path=/"

        let output: SNLHTTPResponse = try await executor.execute()
        XCTAssertEqual(output.body, httpStatusValidBody)
        XCTAssertEqual(output.url, finalURL)
        XCTAssertEqual(output.statusCode, 202)
        XCTAssertEqual(output.headers[.contentType], "application/json; charset=utf-8")
        XCTAssertEqual(output.headers[.custom("x-request-id")], "AbCd-123")
        XCTAssertEqual(output.headers[.custom("set-cookie")], cookie)

        let finished = expectation(description: "HTTP response metadata callback")
        executor.execute { response, error in
            XCTAssertEqual(response?.body, httpStatusValidBody)
            XCTAssertEqual(response?.url, finalURL)
            XCTAssertEqual(response?.statusCode, 202)
            XCTAssertEqual(response?.headers[.contentType], "application/json; charset=utf-8")
            XCTAssertEqual(response?.headers[.custom("X-REQUEST-ID")], "AbCd-123")
            XCTAssertEqual(response?.headers[.custom("Set-Cookie")], cookie)
            XCTAssertNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
    }
}

private let httpStatusValidBody = Data(#"{"value":42}"#.utf8)
private let httpStatusInvalidBody = Data("Internal server error".utf8)

private struct HTTPStatusPayload: Decodable, Sendable {
    let value: Int
}

private func makeHTTPStatusSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HTTPStatusURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeHTTPStatusExecutor(session: URLSession, path: String) -> SNLExecutorPrtcl {
    let resource = SNLResource(provider: SNLProvider(session: session), domain: "swift-net-layer.test")
    let target = SNLTarget(resource: resource, path: path)
    return target.makeExecutor(target: target, resource: resource, method: .get)
}

private final class HTTPStatusURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "swift-net-layer.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if url.path == "/transport-error" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if url.path == "/non-http" {
            let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        if url.path == "/final-response" {
            let response = HTTPURLResponse(
                url: URL(string: "https://swift-net-layer.test/final")!,
                statusCode: 202,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json; charset=utf-8",
                    "X-Request-ID": "AbCd-123",
                    "Set-Cookie": "session=abc; Expires=Wed, 21 Oct 2030 07:28:00 GMT; Path=/"
                ]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: httpStatusValidBody)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let component = url.path.split(separator: "/").first,
              let statusCode = Int(component),
              let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let body = statusCode == 204 ? Data() : (url.lastPathComponent == "invalid" ? httpStatusInvalidBody : httpStatusValidBody)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
extension HTTPStatusURLProtocol: @unchecked Sendable {}
#endif
