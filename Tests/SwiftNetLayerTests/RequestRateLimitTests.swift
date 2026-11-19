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
            XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: now))
            XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: now), now + 1_000_000_000)
            XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: now + 999_999_999), now + 1_000_000_000)
        }
    }

    func testEveryWindowAllowsTheFullRequestLimit() {
        var options = RequestPerSecondOptions(requestLimit: 3)
        options.windowStartNanoseconds = 0

        for second in 0..<4 {
            let now = UInt64(second) * 1_000_000_000
            for _ in 0..<3 {
                XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: now))
            }
            XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: now), now + 1_000_000_000)
        }
    }

    func testWindowExpiresAtItsExactBoundary() {
        var options = RequestPerSecondOptions(requestLimit: 1, timeRangeLimitSecond: 30)
        options.windowStartNanoseconds = 1_500_000_000
        let deadline: UInt64 = 31_500_000_000

        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: 1_900_000_000))
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 3_000_000_000), deadline)
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: deadline - 1), deadline)
        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: deadline))
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: deadline), deadline + 30_000_000_000)
    }

    func testEarlierTimestampResetsWindowWithoutUnsignedUnderflow() {
        var options = RequestPerSecondOptions(requestLimit: 1)
        options.windowStartNanoseconds = 2_000_000_000

        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: 2_000_000_000))
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 2_000_000_000), 3_000_000_000)
        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: 1_000_000_000))
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 1_000_000_000), 2_000_000_000)
        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: 2_000_000_000))
    }

    func testZeroRequestLimitNeverAllowsRequests() {
        var options = RequestPerSecondOptions(requestLimit: 0)
        options.windowStartNanoseconds = 0

        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 0), 1_000_000_000)
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 1_000_000_000), 2_000_000_000)
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: .max), .max)

        options.timeRangeLimitSecond = 0
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 0), .max)
    }

    func testLargeWindowDoesNotOverflowWhenComparingNanoseconds() {
        var options = RequestPerSecondOptions(requestLimit: 1, timeRangeLimitSecond: .max)
        options.windowStartNanoseconds = 0

        XCTAssertNil(options.acquireRequestSlotOrRetryAt(at: 0))
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: 1), .max)
        XCTAssertEqual(options.acquireRequestSlotOrRetryAt(at: .max), .max)
    }

    func testResourceWithoutLimiterAlwaysAllowsRequests() {
        let resource = SNLResource(domain: "swift-net-layer.test")

        for _ in 0..<100 {
            XCTAssertNil(resource.acquireRequestSlotOrRetryAt())
        }
    }

    func testConcurrentRequestsCannotExceedTheLimit() {
        let resource: any SNLResourcePrtcl = SNLResource(
            domain: "swift-net-layer.test",
            requestPerSecondOptions: .init(.init(requestLimit: 25, timeRangeLimitSecond: .max))
        )
        let allowedCount = SafeValue(0)

        DispatchQueue.concurrentPerform(iterations: 500) { _ in
            if resource.acquireRequestSlotOrRetryAt() == nil {
                allowedCount.change { $0 += 1 }
            }
        }

        XCTAssertEqual(allowedCount.value, 25)
        XCTAssertNotNil(resource.acquireRequestSlotOrRetryAt())
    }
}
