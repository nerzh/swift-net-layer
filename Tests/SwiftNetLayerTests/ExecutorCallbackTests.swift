import Dispatch
import Foundation
import SwiftExtensionsPack
import SwiftNetLayer
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ExecutorCallbackTests: XCTestCase {
    func testThrowingModelHandlerIsCalledOnceAfterSuccessfulDecoding() throws {
        let calls = SafeValue(0)

        try makeCallbackExecutor(provider: .init()).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertEqual(model?.value, 42)
            XCTAssertNotNil(response)
            XCTAssertNil(error)
            throw CallbackTestError.handler
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testThrowingModelHandlerIsCalledOnceWithoutData() throws {
        let calls = SafeValue(0)
        let transportError = SNLError("Transport failed")
        let provider = CallbackTestProvider(data: nil, error: transportError, delivery: .synchronous)

        try makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertNotNil(response)
            XCTAssertEqual(error?.reason, transportError.reason)
            throw CallbackTestError.handler
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testThrowingModelHandlerIsCalledOnceAfterDecodingFailure() throws {
        let calls = SafeValue(0)
        let provider = CallbackTestProvider(data: Data("invalid JSON".utf8), delivery: .synchronous)

        try makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, response, error in
            calls.change { $0 += 1 }
            XCTAssertNil(model)
            XCTAssertNotNil(response)
            XCTAssertNotNil(error)
            throw CallbackTestError.handler
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testModelCallbackPreservesTransportErrorWithValidData() throws {
        let calls = SafeValue(0)
        let transportError = SNLError("Transport failed")
        let provider = CallbackTestProvider(error: transportError, delivery: .synchronous)

        try makeCallbackExecutor(provider: provider).execute(model: CallbackPayload.self) { model, _, error in
            calls.change { $0 += 1 }
            XCTAssertEqual(model?.value, 42)
            XCTAssertEqual(error?.reason, transportError.reason)
        }

        XCTAssertEqual(calls.value, 1)
    }

    func testRawWaitExecuteRethrowsHandlerErrorWithoutHanging() throws {
        for delivery in CallbackTestProvider.Delivery.allCases {
            let calls = SafeValue(0)
            let provider = CallbackTestProvider(delivery: delivery)

            let result = try waitForOperation {
                try makeCallbackExecutor(provider: provider).waitExecute { data, response, error in
                    calls.change { $0 += 1 }
                    XCTAssertNotNil(data)
                    XCTAssertNotNil(response)
                    XCTAssertNil(error)
                    throw CallbackTestError.handler
                }
            }

            XCTAssertThrowsError(try result.get()) { error in
                XCTAssertEqual(error as? CallbackTestError, .handler)
            }
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testModelWaitExecuteRethrowsHandlerErrorWithoutHanging() throws {
        for delivery in CallbackTestProvider.Delivery.allCases {
            let calls = SafeValue(0)
            let provider = CallbackTestProvider(delivery: delivery)

            let result = try waitForOperation {
                try makeCallbackExecutor(provider: provider).waitExecute(model: CallbackPayload.self) { model, _, error in
                    calls.change { $0 += 1 }
                    XCTAssertEqual(model?.value, 42)
                    XCTAssertNil(error)
                    throw CallbackTestError.handler
                }
            }

            XCTAssertThrowsError(try result.get()) { error in
                XCTAssertEqual(error as? CallbackTestError, .handler)
            }
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testWaitExecuteReturnsAfterSuccessfulHandlerFinishes() throws {
        for delivery in CallbackTestProvider.Delivery.allCases {
            for useModel in [false, true] {
                let calls = SafeValue(0)
                let provider = CallbackTestProvider(delivery: delivery)

                let result = try waitForOperation {
                    let executor = makeCallbackExecutor(provider: provider)
                    if useModel {
                        try executor.waitExecute(model: CallbackPayload.self) { _, _, _ in
                            calls.change { $0 += 1 }
                        }
                    } else {
                        try executor.waitExecute { _, _, _ in
                            calls.change { $0 += 1 }
                        }
                    }
                    XCTAssertEqual(calls.value, 1)
                }

                XCTAssertNoThrow(try result.get())
                XCTAssertEqual(calls.value, 1)
            }
        }
    }

    func testWaitExecutePropagatesSetupErrorsWithoutWaiting() throws {
        for useModel in [false, true] {
            let calls = SafeValue(0)
            let provider = CallbackTestProvider(delivery: .synchronous, setupError: .setup)

            let result = try waitForOperation {
                let executor = makeCallbackExecutor(provider: provider)
                if useModel {
                    try executor.waitExecute(model: CallbackPayload.self, debug: false) { _, _, _ in
                        calls.change { $0 += 1 }
                    }
                } else {
                    try executor.waitExecute(debug: false) { _, _, _ in
                        calls.change { $0 += 1 }
                    }
                }
            }

            XCTAssertThrowsError(try result.get()) { error in
                XCTAssertEqual(error as? CallbackTestError, .setup)
            }
            XCTAssertEqual(calls.value, 0)
        }
    }

    func testModelWaitExecuteDeliversDecodingErrorOnce() throws {
        for delivery in CallbackTestProvider.Delivery.allCases {
            let calls = SafeValue(0)
            let provider = CallbackTestProvider(data: Data("invalid JSON".utf8), delivery: delivery)

            let result = try waitForOperation {
                try makeCallbackExecutor(provider: provider).waitExecute(model: CallbackPayload.self) { model, _, error in
                    calls.change { $0 += 1 }
                    XCTAssertNil(model)
                    XCTAssertNotNil(error)
                    throw CallbackTestError.handler
                }
            }

            XCTAssertThrowsError(try result.get()) { error in
                XCTAssertEqual(error as? CallbackTestError, .handler)
            }
            XCTAssertEqual(calls.value, 1)
        }
    }

    private func waitForOperation(
        _ operation: @escaping @Sendable () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Result<Void, Error> {
        let finished = expectation(description: "Synchronous execution finishes")
        let outcome = SafeValue<Result<Void, Error>?>(nil)

        DispatchQueue.global().async {
            let result = Result { try operation() }
            outcome.change { $0 = result }
            finished.fulfill()
        }

        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 2), .completed, file: file, line: line)
        return try XCTUnwrap(outcome.value, file: file, line: line)
    }
}

private struct CallbackPayload: Decodable, Sendable {
    let value: Int
}

private enum CallbackTestError: Error, Equatable {
    case handler
    case setup
}

private struct CallbackTestProvider: SNLProviderPrtcl {
    enum Delivery: CaseIterable, Sendable {
        case synchronous
        case asynchronous
    }

    let data: Data?
    let error: SNLError?
    let delivery: Delivery
    let setupError: CallbackTestError?

    init() {
        self.init(delivery: .synchronous)
    }

    init(
        data: Data? = Data(#"{"value":42}"#.utf8),
        error: SNLError? = nil,
        delivery: Delivery,
        setupError: CallbackTestError? = nil
    ) {
        self.data = data
        self.error = error
        self.delivery = delivery
        self.setupError = setupError
    }

    func executeRequest(
        resource: SNLResourcePrtcl,
        request: SNLRequestPrtcl,
        debug: Bool,
        _ handler: @escaping @Sendable (Data?, URLResponse?, SNLError?) throws -> Void
    ) throws {
        if let setupError { throw setupError }
        let data = self.data
        let error = self.error
        let response = URLResponse(url: request.path, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)

        switch delivery {
        case .synchronous:
            try? handler(data, response, error)
        case .asynchronous:
            DispatchQueue.global().async {
                try? handler(data, response, error)
            }
        }
    }
}

private func makeCallbackExecutor(provider: CallbackTestProvider) -> SNLExecutorPrtcl {
    let resource = SNLResource(provider: provider, domain: "swift-net-layer.test")
    let target = SNLTarget(resource: resource, path: "/callback")
    return target.makeExecutor(target: target, resource: resource, method: .get)
}
