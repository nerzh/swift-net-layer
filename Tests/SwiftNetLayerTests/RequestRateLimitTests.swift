import Dispatch
import SwiftExtensionsPack
import XCTest
@testable import SwiftNetLayer

final class RequestRateLimitTests: XCTestCase {
    func testSingleRequestLimitAllowsOneRequestInEveryWindow() {
        var options = RequestPerSecondOptions(requestLimit: 1)
        options.windowStartNanoseconds = 0

        for second in 0..<4 {
            let now = UInt64(second) * 1_000_000_000
            XCTAssertTrue(options.allowRequest(at: now))
            XCTAssertFalse(options.allowRequest(at: now))
            XCTAssertFalse(options.allowRequest(at: now + 999_999_999))
        }
    }

    func testEveryWindowAllowsTheFullRequestLimit() {
        var options = RequestPerSecondOptions(requestLimit: 3)
        options.windowStartNanoseconds = 0

        for second in 0..<4 {
            let now = UInt64(second) * 1_000_000_000
            for _ in 0..<3 {
                XCTAssertTrue(options.allowRequest(at: now))
            }
            XCTAssertFalse(options.allowRequest(at: now))
        }
    }

    func testWindowExpiresAtItsExactBoundary() {
        var options = RequestPerSecondOptions(requestLimit: 1, timeRangeLimitSecond: 2)
        options.windowStartNanoseconds = 1_500_000_000

        XCTAssertTrue(options.allowRequest(at: 1_900_000_000))
        XCTAssertFalse(options.allowRequest(at: 3_000_000_000))
        XCTAssertFalse(options.allowRequest(at: 3_499_999_999))
        XCTAssertTrue(options.allowRequest(at: 3_500_000_000))
        XCTAssertFalse(options.allowRequest(at: 3_500_000_000))
    }

    func testEarlierTimestampResetsWindowWithoutUnsignedUnderflow() {
        var options = RequestPerSecondOptions(requestLimit: 1)
        options.windowStartNanoseconds = 2_000_000_000

        XCTAssertTrue(options.allowRequest(at: 2_000_000_000))
        XCTAssertFalse(options.allowRequest(at: 2_000_000_000))
        XCTAssertTrue(options.allowRequest(at: 1_000_000_000))
        XCTAssertFalse(options.allowRequest(at: 1_000_000_000))
        XCTAssertTrue(options.allowRequest(at: 2_000_000_000))
    }

    func testZeroRequestLimitNeverAllowsRequests() {
        var options = RequestPerSecondOptions(requestLimit: 0)
        options.windowStartNanoseconds = 0

        for now in [UInt64(0), 1_000_000_000, UInt64.max] {
            XCTAssertFalse(options.allowRequest(at: now))
        }
    }

    func testLargeWindowDoesNotOverflowWhenComparingNanoseconds() {
        var options = RequestPerSecondOptions(requestLimit: 1, timeRangeLimitSecond: .max)
        options.windowStartNanoseconds = 0

        XCTAssertTrue(options.allowRequest(at: 0))
        XCTAssertFalse(options.allowRequest(at: UInt64.max))
    }

    func testResourceWithoutLimiterAlwaysAllowsRequests() {
        let resource = SNLResource(domain: "swift-net-layer.test")

        for _ in 0..<100 {
            XCTAssertTrue(resource.allowRequest)
        }
    }

    func testConcurrentRequestsCannotExceedTheLimit() {
        let resource = SNLResource(
            domain: "swift-net-layer.test",
            requestPerSecondOptions: .init(.init(requestLimit: 25, timeRangeLimitSecond: .max))
        )
        let allowedCount = SafeValue(0)

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            if resource.allowRequest {
                allowedCount.change { $0 += 1 }
            }
        }

        XCTAssertEqual(allowedCount.value, 25)
        XCTAssertFalse(resource.allowRequest)
    }
}
