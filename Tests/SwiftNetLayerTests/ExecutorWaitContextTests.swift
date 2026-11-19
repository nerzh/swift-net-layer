import Dispatch
import Foundation
import SwiftExtensionsPack
import SwiftNetLayer
import XCTest

final class ExecutorWaitContextTests: XCTestCase, @unchecked Sendable {
    func testWaitRejectsCustomProviderOnItsDispatchQueue() async {
        let queue = DispatchQueue(label: "SwiftNetLayerTests.custom-provider")
        let provider = ContextProvider(context: .dispatchQueue(queue), failIfExecuted: true)

        await checkRejection(provider: provider, requests: provider.requests) { operation in
            queue.async(execute: operation)
        }
    }

    func testWaitRejectsCustomProviderOnItsOperationQueue() async {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let provider = ContextProvider(context: .operationQueue(queue), failIfExecuted: true)

        await checkRejection(provider: provider, requests: provider.requests) { operation in
            queue.addOperation(operation)
        }
    }

    func testWaitRejectsCustomProviderOnMainCallbackQueue() async {
        let provider = ContextProvider(context: .dispatchQueue(.main), failIfExecuted: true)

        await checkRejection(provider: provider, requests: provider.requests) { operation in
            DispatchQueue.main.async(execute: operation)
        }
    }

    func testWaitRejectsUnsupportedProviderBeforeCallingIt() async {
        let provider = WaitUnsupportedProvider()

        await checkRejection(
            provider: provider, requests: provider.requests,
            reason: "This provider does not support waitExecute; use execute instead"
        ) { operation in
            DispatchQueue.global().async(execute: operation)
        }
    }

    func testWaitOnMainQueueAllowsUncheckedOrOtherCallbackQueues() async {
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        let contexts: [SNLCallbackContext] = [
            .unchecked,
            .dispatchQueue(DispatchQueue(label: "SwiftNetLayerTests.custom-response")),
            .operationQueue(operationQueue)
        ]

        for context in contexts {
            for useModel in [false, true] {
                let provider = ContextProvider(context: context)
                let calls = SafeValue(0)
                let finished = expectation(description: "Main queue wait finishes")

                DispatchQueue.main.async {
                    let executor = makeWaitExecutor(provider: provider)
                    let checkResult: @Sendable (SNLHTTPResponse?, SNLError?) -> Void = { response, error in
                        calls.change { $0 += 1 }
                        XCTAssertEqual(response?.body, Data(#"{"value":42}"#.utf8))
                        XCTAssertNil(error)
                    }
                    if useModel {
                        executor.waitExecute(model: WaitPayload.self) { model, response, error in
                            XCTAssertEqual(model?.value, 42)
                            checkResult(response, error)
                        }
                    } else {
                        executor.waitExecute(checkResult)
                    }
                    XCTAssertEqual(calls.value, 1)
                    XCTAssertEqual(provider.requests.value, 1)
                    finished.fulfill()
                }

                await fulfillment(of: [finished], timeout: 2)
                XCTAssertEqual(calls.value, 1)
            }
        }
    }

    func testNonblockingExecuteCanBeCalledOnCustomCallbackQueue() async {
        let provider = ContextProvider(context: .dispatchQueue(.main))
        let finished = expectation(description: "Nonblocking request on the callback queue finishes")

        DispatchQueue.main.async {
            makeWaitExecutor(provider: provider).execute(model: WaitPayload.self) { model, response, error in
                XCTAssertEqual(model?.value, 42)
                XCTAssertNotNil(response)
                XCTAssertNil(error)
                finished.fulfill()
            }
        }

        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(provider.requests.value, 1)
    }

    func testWaitUnsupportedStillAllowsCallbackAndAsyncExecution() async throws {
        let provider = WaitUnsupportedProvider()
        let executor = makeWaitExecutor(provider: provider)
        let finished = expectation(description: "Provider without wait support handles callbacks")
        executor.execute(model: WaitPayload.self) { model, response, error in
            XCTAssertEqual(model?.value, 42)
            XCTAssertNotNil(response)
            XCTAssertNil(error)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)

        let output = try await executor.execute(model: WaitPayload.self)
        XCTAssertEqual(output.model.value, 42)
        XCTAssertEqual(output.response.body, Data(#"{"value":42}"#.utf8))
        XCTAssertEqual(provider.requests.value, 2)
    }

    private func checkRejection(
        provider: any SNLProviderPrtcl,
        requests: SafeValue<Int>,
        reason: String = "waitExecute cannot block the provider callback queue; use execute instead",
        schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
    ) async {
        for useModel in [false, true] {
            let finished = expectation(description: "Unsafe wait is rejected through the provider protocol")
            let calls = SafeValue(0)

            schedule {
                let executor = makeWaitExecutor(provider: provider)
                let checkResult: @Sendable (SNLHTTPResponse?, SNLError?) -> Void = { response, error in
                    calls.change { $0 += 1 }
                    XCTAssertNil(response)
                    XCTAssertEqual(error?.reason, reason)
                }
                if useModel {
                    executor.waitExecute(model: WaitPayload.self, debug: false) { model, response, error in
                        XCTAssertNil(model)
                        checkResult(response, error)
                    }
                } else {
                    executor.waitExecute(debug: false, checkResult)
                }
                XCTAssertEqual(calls.value, 1)
                XCTAssertEqual(requests.value, 0)
                finished.fulfill()
            }

            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(calls.value, 1)
            XCTAssertEqual(requests.value, 0)
        }
    }
}

private struct WaitPayload: Decodable, Sendable {
    let value: Int
}

private struct ContextProvider: SNLProviderPrtcl {
    let callbackContext: SNLCallbackContext
    let requests = SafeValue(0)
    let failIfExecuted: Bool

    init() {
        self.init(context: .unchecked)
    }

    init(context: SNLCallbackContext, failIfExecuted: Bool = false) {
        self.callbackContext = context
        self.failIfExecuted = failIfExecuted
    }

    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void
    ) {
        requests.change { $0 += 1 }
        if failIfExecuted {
            // Fail synchronously if the executor's guard regresses, keeping rejection tests bounded.
            handler(nil, SNLError("Unexpected provider execution"))
            return
        }
        let response = SNLHTTPResponse(url: request.path, statusCode: 200, body: Data(#"{"value":42}"#.utf8))
        let complete: @Sendable () -> Void = { handler(response, nil) }
        switch callbackContext {
        case .waitUnsupported, .unchecked:
            complete()
        case let .dispatchQueue(queue):
            queue.async(execute: complete)
        case let .operationQueue(queue):
            queue.addOperation(complete)
        }
    }

    func executeRequest(resource: SNLResourcePrtcl, request: SNLRequestPrtcl, debug: Bool) async throws -> SNLHTTPResponse {
        requests.change { $0 += 1 }
        if failIfExecuted { throw SNLError("Unexpected provider execution") }
        return SNLHTTPResponse(url: request.path, statusCode: 200, body: Data(#"{"value":42}"#.utf8))
    }
}

private struct WaitUnsupportedProvider: SNLProviderPrtcl {
    let callbackContext: SNLCallbackContext = .waitUnsupported
    let requests = SafeValue(0)

    init() {}

    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void
    ) {
        handler(response(for: request), nil)
    }

    func executeRequest(resource: SNLResourcePrtcl, request: SNLRequestPrtcl, debug: Bool) async throws -> SNLHTTPResponse {
        response(for: request)
    }

    private func response(for request: SNLRequestPrtcl) -> SNLHTTPResponse {
        requests.change { $0 += 1 }
        return SNLHTTPResponse(url: request.path, statusCode: 200, body: Data(#"{"value":42}"#.utf8))
    }
}

private func makeWaitExecutor(provider: any SNLProviderPrtcl) -> SNLExecutorPrtcl {
    let resource = SNLResource(provider: provider, domain: "swift-net-layer.test")
    let target = SNLTarget(resource: resource, path: "/wait-context")
    return target.makeExecutor(target: target, resource: resource, method: .get)
}
