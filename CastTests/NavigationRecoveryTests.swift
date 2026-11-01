import XCTest
import simd
@testable import Cast

final class NavigationRecoveryTests: XCTestCase {
    func testDetourChecksBothLegsAndTriesOtherSide() throws {
        let start = SIMD3<Float>.zero
        let goal = SIMD3<Float>(0, 0, 0.3)
        var checkedSecondLeg = false
        let waypoint = NavigationRecovery.detour(from: start, to: goal, radius: 0.04) { a, b in
            if b == goal {
                checkedSecondLeg = true
                return a.x < 0 // First side has a blocked return route.
            }
            return true
        }
        XCTAssertTrue(checkedSecondLeg)
        XCTAssertLessThan(try XCTUnwrap(waypoint).x, 0)
        XCTAssertEqual(waypoint?.y, 0)
    }

    func testDetourDoesNotInventRouteAcrossBlockedOrInvalidSpace() {
        XCTAssertNil(NavigationRecovery.detour(from: .zero, to: [0, 0, 0.3], radius: 0.04) { _, _ in false })
        XCTAssertNil(NavigationRecovery.detour(from: .zero, to: .zero, radius: 0.04) { _, _ in true })
        XCTAssertNil(NavigationRecovery.detour(from: .zero, to: [.nan, 0, 0], radius: 0.04) { _, _ in true })
    }

    func testRecoveryRequiresContinuousSupportAndResetsAfterGap() {
        var recovery = SupportRecovery()
        XCTAssertFalse(recovery.observe(supported: true, now: 0))
        XCTAssertFalse(recovery.observe(supported: true, now: 2)) // Camera gap is not stable evidence.
        for i in 1...4 { XCTAssertFalse(recovery.observe(supported: true, now: 2 + Double(i) * 0.2)) }
        XCTAssertFalse(recovery.observe(supported: false, now: 3))
        for i in 0...4 { XCTAssertFalse(recovery.observe(supported: true, now: 4 + Double(i) * 0.2)) }
        XCTAssertTrue(recovery.observe(supported: true, now: 5))
    }

    func testRecoveryStopsRetryingAfterTwoFailedReleases() {
        var recovery = SupportRecovery()
        var releases = 0
        for i in 0...50 {
            if recovery.observe(supported: true, now: Double(i) * 0.1) { releases += 1 }
        }
        XCTAssertEqual(releases, 2)
        XCTAssertEqual(recovery.attempts, 2)
    }
}
