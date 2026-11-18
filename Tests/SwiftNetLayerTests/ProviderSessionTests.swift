import Foundation
import SwiftExtensionsPack
import SwiftNetLayer
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ProviderSessionTests: XCTestCase, @unchecked Sendable {
    func testRequestTimeoutPreservesDelegateAndQueue() async throws {
        try await checkTimeoutSession(requestTimeout: 17, resourceTimeout: nil)
    }

    func testResourceTimeoutPreservesDelegateAndQueue() async throws {
        try await checkTimeoutSession(requestTimeout: nil, resourceTimeout: 23)
    }

    func testBothTimeoutsPreserveDelegateAndQueue() async throws {
        try await checkTimeoutSession(requestTimeout: 17, resourceTimeout: 23)
    }

    private func checkTimeoutSession(requestTimeout: TimeInterval?, resourceTimeout: TimeInterval?) async throws {
        for callback in [false, true] {
            let invalidated = expectation(description: "Temporary session notifies the original delegate")
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let delegate = TimeoutSessionDelegate(queue: queue, invalidated: invalidated)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SessionTestURLProtocol.self]
            configuration.timeoutIntervalForRequest = 61
            configuration.timeoutIntervalForResource = 127
            let originalSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
            delegate.originalSessionID.change { $0 = ObjectIdentifier(originalSession) }
            defer { originalSession.invalidateAndCancel() }

            let provider = SNLProvider(session: originalSession)
            let resource = SNLResource(provider: provider, domain: "swift-net-layer.test")
            let request = SNLRequest(
                method: .get,
                path: URL(string: "/session")!,
                dynamicPathsParts: nil,
                timeoutIntervalForRequest: requestTimeout,
                timeoutIntervalForResource: resourceTimeout
            )

            let data = try await execute(provider, resource: resource, request: request, callback: callback)
            XCTAssertEqual(data, Data("ok".utf8))
            await fulfillment(of: [invalidated], timeout: 2)

            let observations = delegate.observations.value
            XCTAssertEqual(observations.count, 1)
            let observation = try XCTUnwrap(observations.first)
            XCTAssertTrue(observation.preservesDelegate)
            XCTAssertTrue(observation.preservesQueue)
            XCTAssertTrue(observation.callbackUsesQueue)
            XCTAssertNil(observation.invalidationError)
            XCTAssertEqual(observation.requestTimeout, requestTimeout ?? 61)
            XCTAssertEqual(observation.resourceTimeout, resourceTimeout ?? 127)
            XCTAssertEqual(originalSession.configuration.timeoutIntervalForRequest, 61)
            XCTAssertEqual(originalSession.configuration.timeoutIntervalForResource, 127)
            XCTAssertFalse(delegate.originalSessionInvalidated.value)

            var originalRequest = request
            originalRequest.timeoutIntervalForRequest = nil
            originalRequest.timeoutIntervalForResource = nil
            let originalData = try await execute(provider, resource: resource, request: originalRequest, callback: callback)
            XCTAssertEqual(originalData, Data("ok".utf8))
            XCTAssertFalse(delegate.originalSessionInvalidated.value)
        }
    }

    private func execute(
        _ provider: SNLProvider,
        resource: SNLResource,
        request: SNLRequest,
        callback: Bool
    ) async throws -> Data {
        if callback {
            return try await withCheckedThrowingContinuation { continuation in
                provider.executeRequest(resource: resource, request: request, debug: false) { response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: response.body)
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
            }
        }

        return try await provider.executeRequest(resource: resource, request: request, debug: false).body
    }
}

private final class TimeoutSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    struct Observation {
        let preservesDelegate: Bool
        let preservesQueue: Bool
        let callbackUsesQueue: Bool
        let invalidationError: Error?
        let requestTimeout: TimeInterval
        let resourceTimeout: TimeInterval
    }

    let originalSessionID = SafeValue<ObjectIdentifier?>(nil)
    let originalSessionInvalidated = SafeValue(false)
    let observations = SafeValue<[Observation]>([])
    private let queue: OperationQueue
    private let invalidated: XCTestExpectation

    init(queue: OperationQueue, invalidated: XCTestExpectation) {
        self.queue = queue
        self.invalidated = invalidated
        super.init()
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        if originalSessionID.value == ObjectIdentifier(session) {
            originalSessionInvalidated.change { $0 = true }
            return
        }

        let observation = Observation(
            preservesDelegate: session.delegate === self,
            preservesQueue: session.delegateQueue === queue,
            callbackUsesQueue: OperationQueue.current === queue,
            invalidationError: error,
            requestTimeout: session.configuration.timeoutIntervalForRequest,
            resourceTimeout: session.configuration.timeoutIntervalForResource
        )
        observations.change { $0.append(observation) }
        invalidated.fulfill()
    }
}

private final class SessionTestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "swift-net-layer.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

#if !canImport(FoundationNetworking)
extension SessionTestURLProtocol: @unchecked Sendable {}
#endif
