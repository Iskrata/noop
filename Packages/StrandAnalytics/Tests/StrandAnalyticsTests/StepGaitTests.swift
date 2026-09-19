import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class StepGaitTests: XCTestCase {
    /// One tick per second over [0, n), the class for each second given by `cls`.
    private func ticks(_ n: Int, _ cls: (Int) -> Int?) -> [StepSample] {
        (0..<n).map { StepSample(ts: $0, counter: $0, activityClass: cls($0)) }
    }

    func testMostlyWalkTicksIsWalk() {
        let steps = ticks(900) { $0 % 10 < 8 ? 1 : 0 }   // 80 % walk
        XCTAssertEqual(StepGait.classify(steps, start: 0, end: 899), .walk)
    }

    func testRunDominantIsRun() {
        let steps = ticks(600) { $0 % 10 < 6 ? 2 : 1 }
        XCTAssertEqual(StepGait.classify(steps, start: 0, end: 599), .run)
    }

    func testStrengthLikeWindowIsNotOnFoot() {
        let steps = ticks(3600) { $0 % 10 < 3 ? 1 : 0 }  // 30 % walk, like a gym session
        XCTAssertNil(StepGait.classify(steps, start: 0, end: 3599))
    }

    func testNoClassedTicksIsNil() {
        XCTAssertNil(StepGait.classify(ticks(900) { _ in nil }, start: 0, end: 899))
        XCTAssertNil(StepGait.classify([], start: 0, end: 899))
    }

    func testSparseCoverageIsNil() {
        // Walk ticks for only the first third of the window: not enough evidence.
        let steps = ticks(300) { _ in 1 }
        XCTAssertNil(StepGait.classify(steps, start: 0, end: 899))
    }

    func testOnlyTicksInsideTheWindowCount() {
        let steps = ticks(2000) { $0 < 1000 ? 0 : 1 }
        XCTAssertEqual(StepGait.classify(steps, start: 1000, end: 1899), .walk)
        XCTAssertNil(StepGait.classify(steps, start: 0, end: 899))
    }
}
