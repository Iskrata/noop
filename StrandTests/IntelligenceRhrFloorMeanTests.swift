import XCTest
@testable import Strand

/// Pins the resting-HR strap-log line (#691). FORK: NOOP's `restingHr` is the primary session's whole-session
/// mean; the line carries it beside the deep-sleep mean (`deepMean`, the day's figure until 2026-10-03), the
/// lowest 5-min bin (`floor`) and the whole in-bed mean, so a "NOOP reads differently from my other app"
/// report is explainable from the log. `rhrFloorMeanLogLine` is the pure formatter the loop calls; it's
/// tested directly (no store). FORK: diverges from the Android `IntelligenceRhrFloorMeanTest`.
@MainActor
final class IntelligenceRhrFloorMeanTests: XCTestCase {

    private typealias IE = IntelligenceEngine

    func testAllThreeStatisticsShipOnOneLine() {
        let bpms = [48, 50, 52, 55, 58, 60, 62]   // mean = 55.0 → "55"
        let line = IE.rhrFloorMeanLogLine(day: "2026-06-12", restingHr: 55, deepMean: 51, floor: 48,
                                         inBedBpms: bpms)
        XCTAssertEqual(line,
            "rhr day=2026-06-12 rhr=55 deepMean=51 floor=48 nightMean=55 inBedSamples=7 "
            + "(rhr = primary-session mean = NOOP RHR; deepMean = primary-session deep-sleep mean; "
            + "floor = lowest 5-min bin; mean = whole in-bed span)")
    }

    func testMeanRoundsToNearest() {
        // 50,51,52,54 → 207/4 = 51.75 → rounds to 52 (banker-free .rounded()), matching Kotlin Math.round.
        let line = IE.rhrFloorMeanLogLine(day: "2026-06-13", restingHr: 52, deepMean: 51, floor: 50,
                                         inBedBpms: [50, 51, 52, 54])
        XCTAssertTrue(line.contains("rhr=52 deepMean=51 floor=50 nightMean=52 inBedSamples=4"), line)
    }

    func testEmptyInBedAndMissingFloorReadNil() {
        // A resting HR but no HR sample inside a matched session (edge): mean, deep mean and floor read
        // "nil", not 0, and the line is still emitted so the night stays visible in the log.
        let line = IE.rhrFloorMeanLogLine(day: "2026-06-12", restingHr: 47, deepMean: nil, floor: nil,
                                          inBedBpms: [])
        XCTAssertEqual(line,
            "rhr day=2026-06-12 rhr=47 deepMean=nil floor=nil nightMean=nil inBedSamples=0 "
            + "(rhr = primary-session mean = NOOP RHR; deepMean = primary-session deep-sleep mean; "
            + "floor = lowest 5-min bin; mean = whole in-bed span)")
    }

    func testLineCarriesNoEmDash() {
        // House style: never an em-dash in shared text.
        let line = IE.rhrFloorMeanLogLine(day: "2026-06-12", restingHr: 54, deepMean: 50, floor: 48,
                                          inBedBpms: [48, 60])
        XCTAssertFalse(line.contains("—"))
    }
}
