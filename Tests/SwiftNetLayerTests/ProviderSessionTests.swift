import Dispatch
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

    func testWaitExecuteRejectsCallsOnSessionDelegateQueue() async {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: queue)
        defer { session.invalidateAndCancel() }

        await checkWaitExecuteRejection(session: session) { operation in
            queue.addOperation(operation)
        }
    }

    func testWaitExecuteRejectsCallsOnMainDelegateQueue() async {
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: .main)
        defer { session.invalidateAndCancel() }

        await checkWaitExecuteRejection(session: session) { operation in
            DispatchQueue.main.async(execute: operation)
        }
    }

    func testWaitExecuteRejectsCallsOnUnderlyingDelegateQueue() async {
        let underlyingQueue = DispatchQueue(label: "SwiftNetLayerTests.session-delegate")
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = underlyingQueue
        let session = URLSession(configuration: .ephemeral, delegate: nil, delegateQueue: queue)
        defer { session.invalidateAndCancel() }

        await checkWaitExecuteRejection(session: session) { operation in
            underlyingQueue.async(execute: operation)
        }
    }

    func testWaitExecuteCompletesWhenCalledOutsideDelegateQueue() async {
        let backgroundQueue = OperationQueue()
        backgroundQueue.maxConcurrentOperationCount = 1

        for queue in [backgroundQueue, OperationQueue.main] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SessionTestURLProtocol.self]
            let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: queue)
            defer { session.invalidateAndCancel() }
            let finished = expectation(description: "Waiting outside the delegate queue finishes")
            let calls = SafeValue(0)

            DispatchQueue.global().async {
                let resource = SNLResource(provider: SNLProvider(session: session), domain: "swift-net-layer.test")
                let target = SNLTarget(resource: resource, path: "/session")
                let executor = target.makeExecutor(target: target, resource: resource, method: .get)
                executor.waitExecute { response, error in
                    calls.change { $0 += 1 }
                    XCTAssertEqual(response?.body, Data("ok".utf8))
                    XCTAssertNil(error)
                    XCTAssertTrue(OperationQueue.current === queue)
                }
                XCTAssertEqual(calls.value, 1)
                finished.fulfill()
            }

            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(calls.value, 1)
        }
    }

    private func checkWaitExecuteRejection(
        session: URLSession,
        schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
    ) async {
        for useModel in [false, true] {
            for overrideTimeout in [false, true] {
                let finished = expectation(description: "Unsafe wait is rejected before starting a request")
                let encodings = SafeValue(0)
                let calls = SafeValue(0)

                schedule {
                    let resource = SNLResource(
                        provider: SNLProvider(session: session), domain: "swift-net-layer.test",
                        requestPerSecondOptions: SafeValue(RequestPerSecondOptions(requestLimit: 1, timeRangeLimitSecond: 3600))
                    )
                    let target = SNLTarget(resource: resource, path: "/session")
                    let executor = target.makeExecutor(
                        target: target, resource: resource, method: .post,
                        body: .json(WaitGuardBody(encodings: encodings)),
                        timeoutIntervalForRequest: overrideTimeout ? 17 : nil
                    )
                    let checkResult: @Sendable (SNLHTTPResponse?, SNLError?) -> Void = { response, error in
                        calls.change { $0 += 1 }
                        XCTAssertNil(response)
                        XCTAssertTrue(
                            error?.reason.hasSuffix("waitExecute cannot block the provider callback queue; use execute instead") == true,
                            error?.reason ?? "Missing error"
                        )
                    }

                    if useModel {
                        executor.waitExecute(model: String.self) { model, response, error in
                            XCTAssertNil(model)
                            checkResult(response, error)
                        }
                    } else {
                        executor.waitExecute(checkResult)
                    }

                    XCTAssertEqual(calls.value, 1)
                    XCTAssertEqual(encodings.value, 0)
                    XCTAssertNil(resource.acquireRequestSlotOrRetryAt())
                    finished.fulfill()
                }

                await fulfillment(of: [finished], timeout: 2)
                XCTAssertEqual(calls.value, 1)
                XCTAssertEqual(encodings.value, 0)
            }
        }
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

private struct WaitGuardBody: Encodable {
    let encodings: SafeValue<Int>

    func encode(to encoder: Encoder) throws {
        encodings.change { $0 += 1 }
        // Fail synchronously if the guard regresses so the test cannot deadlock.
        throw SNLError("The request body must not be encoded on the delegate queue")
    }
}

private final class TimeoutSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    struct Observation {
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

        // Delivery to this delegate verifies preservation; session.delegate may already be cleared during invalidation.
        let observation = Observation(
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
