import Dispatch
import Foundation
import SwiftExtensionsPack
import SwiftNetLayer
import XCTest

final class ExecutorCallbackTests: XCTestCase {
    func testRawHandlerReceivesBodyAndMetadataOnce() {
        let calls = SafeValue(0)

        makeCallbackExecutor(provider: .init()).execute { response, error in
            calls.change { $0 += 1 }
            XCTAssertEqual(response?.body, Data(#"{"value":42}"#.utf8))
            XCTAssertEqual(response?.statusCode, 200)
            XCTAssertNil(error)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testModelHandlerIsCalledOnceAfterSuccessfulDecoding() {
        let calls = SafeValue(0)

        makeCallbackExecutor(provider: .init()).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertEqual(model?.value, 42)
            XCTAssertEqual(response?.body, Data(#"{"value":42}"#.utf8))
            XCTAssertNil(error)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testModelHandlerIsCalledOnceWithoutResponse() {
        let calls = SafeValue(0)
        let transportError = SNLError("Transport failed")
        let provider = CallbackTestProvider(data: nil, error: transportError, delivery: .synchronous)

        makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertNil(response)
            XCTAssertEqual(error?.reason, transportError.reason)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testDecodingFailurePreservesResponseAndCallsHandlerOnce() {
        let calls = SafeValue(0)
        let body = Data("invalid JSON".utf8)
        let provider = CallbackTestProvider(data: body, delivery: .synchronous)

        makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertEqual(response?.body, body)
            XCTAssertNotNil(error)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testModelCallbackPreservesProviderErrorWithoutDecodingResponse() {
        let calls = SafeValue(0)
        let providerError = SNLError("Provider failed")
        let provider = CallbackTestProvider(error: providerError, delivery: .synchronous)

        makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertNotNil(response)
            XCTAssertEqual(error?.reason, providerError.reason)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testMissingProviderResultIsReportedAsAnError() {
        let calls = SafeValue(0)
        let provider = CallbackTestProvider(data: nil, delivery: .synchronous)

        makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertNil(response)
            XCTAssertTrue(error?.reason.contains("Missing HTTP response") == true)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testWaitExecuteReturnsAfterSuccessfulHandlerFinishes() {
        for delivery in CallbackTestProvider.Delivery.allCases {
            for useModel in [false, true] {
                let calls = SafeValue(0)
                let provider = CallbackTestProvider(delivery: delivery)

                waitForOperation {
                    let executor = makeCallbackExecutor(provider: provider)
                    if useModel {
                        executor.waitExecute(model: CallbackPayload.self) { model, response, error in
                            calls.change { $0 += 1 }
                            XCTAssertEqual(model?.value, 42)
                            XCTAssertNotNil(response)
                            XCTAssertNil(error)
                        }
                    } else {
                        executor.waitExecute { response, error in
                            calls.change { $0 += 1 }
                            XCTAssertNotNil(response)
                            XCTAssertNil(error)
                        }
                    }
                    XCTAssertEqual(calls.value, 1)
                }

                XCTAssertEqual(calls.value, 1)
            }
        }
    }

    func testWaitExecuteDeliversImmediateAndAsynchronousErrorsWithoutHanging() {
        for delivery in CallbackTestProvider.Delivery.allCases {
            for useModel in [false, true] {
                let calls = SafeValue(0)
                let providerError = SNLError("Request failed")
                let provider = CallbackTestProvider(data: nil, error: providerError, delivery: delivery)

                waitForOperation {
                    let executor = makeCallbackExecutor(provider: provider)
                    if useModel {
                        executor.waitExecute(model: CallbackPayload.self, debug: false) { model, response, error in
                            calls.change { $0 += 1 }
                            XCTAssertNil(model)
                            XCTAssertNil(response)
                            XCTAssertEqual(error?.reason, providerError.reason)
                        }
                    } else {
                        executor.waitExecute(debug: false) { response, error in
                            calls.change { $0 += 1 }
                            XCTAssertNil(response)
                            XCTAssertEqual(error?.reason, providerError.reason)
                        }
                    }
                }

                XCTAssertEqual(calls.value, 1)
            }
        }
    }

    func testModelWaitExecuteDeliversDecodingErrorOnce() {
        for delivery in CallbackTestProvider.Delivery.allCases {
            let calls = SafeValue(0)
            let body = Data("invalid JSON".utf8)
            let provider = CallbackTestProvider(data: body, delivery: delivery)

            waitForOperation {
                makeCallbackExecutor(provider: provider).waitExecute(model: CallbackPayload.self) { model, response, error in
                    calls.change { $0 += 1 }
                    XCTAssertNil(model)
                    XCTAssertEqual(response?.body, body)
                    XCTAssertNotNil(error)
                }
            }

            XCTAssertEqual(calls.value, 1)
        }
    }

    private func waitForOperation(
        _ operation: @escaping @Sendable () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let finished = expectation(description: "Synchronous execution finishes")

        DispatchQueue.global().async {
            operation()
            finished.fulfill()
        }

        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 2), .completed, file: file, line: line)
    }
}

private struct CallbackPayload: Decodable, Sendable {
    let value: Int
}

private struct CallbackTestProvider: SNLProviderPrtcl {
    enum Delivery: CaseIterable, Sendable {
        case synchronous
        case asynchronous
    }

    let data: Data?
    let error: SNLError?
    let delivery: Delivery

    var callbackContext: SNLCallbackContext {
        switch delivery {
        case .synchronous: return .unchecked
        case .asynchronous: return .dispatchQueue(.global())
        }
    }

    init() {
        self.init(delivery: .synchronous)
    }

    init(
        data: Data? = Data(#"{"value":42}"#.utf8),
        error: SNLError? = nil,
        delivery: Delivery
    ) {
        self.data = data
        self.error = error
        self.delivery = delivery
    }

    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (SNLHTTPResponse?, SNLError?) -> Void
    ) {
        let error = self.error
        let response = data.map { SNLHTTPResponse(url: request.path, statusCode: 200, body: $0) }

        switch delivery {
        case .synchronous:
            handler(response, error)
        case .asynchronous:
            DispatchQueue.global().async {
                handler(response, error)
            }
        }
    }

    func executeRequest(resource: SNLResourcePrtcl, request: SNLRequestPrtcl, debug: Bool) async throws -> SNLHTTPResponse {
        if let error { throw error }
        guard let data else { throw SNLError("Missing HTTP response") }
        return SNLHTTPResponse(url: request.path, statusCode: 200, body: data)
    }
}

private func makeCallbackExecutor(provider: CallbackTestProvider) -> SNLExecutorPrtcl {
    let resource = SNLResource(provider: provider, domain: "swift-net-layer.test")
    let target = SNLTarget(resource: resource, path: "/callback")
    return target.makeExecutor(target: target, resource: resource, method: .get)
}
