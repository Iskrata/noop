import XCTest
@testable import Strand
import WhoopStore

/// Fork: the Today coaching line — the today-vs-baseline digest it is built on, and the shortening that
/// keeps it to one short sentence under the rings.
@MainActor
final class CoachingLineTests: XCTestCase {

    private func day(_ key: String, sleepMin: Double?, hrv: Double?, rhr: Int?, charge: Double?, effort: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: sleepMin, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: charge, strain: effort, exerciseCount: nil)
    }

    func testDigestComparesTodayWithPriorAveragesOnly() {
        var days = (1...9).map { day(String(format: "2026-09-%02d", $0), sleepMin: 480, hrv: 60, rhr: 50, charge: 70, effort: 10) }
        days[8] = day("2026-09-09", sleepMin: 480, hrv: 60, rhr: 50, charge: 70, effort: 18)   // yesterday
        days.append(day("2026-09-10", sleepMin: 360, hrv: 40, rhr: 56, charge: 35, effort: 2))  // today
        let digest = AICoachEngine.coachingDigest(days: days, dayKey: "2026-09-10", charge: 38, rest: 61)

        XCTAssertTrue(digest.contains("charge: 38% (7d avg 70, 30d avg 70)"), digest)   // on-screen charge, today excluded
        XCTAssertTrue(digest.contains("rest score: 61%"), digest)
        XCTAssertTrue(digest.contains("sleep: 6.0h (7d avg 8.0, 30d avg 8.0)"), digest)
        XCTAssertTrue(digest.contains("HRV: 40 ms (7d avg 60, 30d avg 60)"), digest)
        XCTAssertTrue(digest.contains("resting HR: 56 bpm"), digest)
        XCTAssertTrue(digest.contains("yesterday's effort: 18.0 (7d avg 11.1)"), digest)  // days 3…9
    }

    func testDigestMarksMissingValues() {
        let digest = AICoachEngine.coachingDigest(days: [], dayKey: "2026-09-10", charge: 50, rest: 70)
        XCTAssertTrue(digest.contains("HRV: — ms (7d avg —, 30d avg —)"), digest)
        XCTAssertTrue(digest.contains("yesterday's effort: — (7d avg —)"), digest)
    }

    func testShortLineIsKeptAndCleaned() {
        XCTAssertEqual(AICoachEngine.shortenedCoachingLine("  \"**HRV** is 20% under your norm, arr — keep it to easy zone 2 today.\"\n"),
                       "HRV is 20% under your norm, arr — keep it to easy zone 2 today.")
        XCTAssertNil(AICoachEngine.shortenedCoachingLine("  \n "))
    }

    func testLongReplyIsCutToTheFirstSentenceThenCapped() {
        let long = "Charge is up to 82, well above your 30-day 64, so arr, go hard today with intervals or a long ride. "
            + "Also make sure you drink water and stretch and sleep early tonight."
        XCTAssertEqual(AICoachEngine.shortenedCoachingLine(long),
                       "Charge is up to 82, well above your 30-day 64, so arr, go hard today with intervals or a long ride.")
        let runOn = Array(repeating: "word", count: 40).joined(separator: " ")
        let capped = AICoachEngine.shortenedCoachingLine(runOn)
        XCTAssertEqual(capped?.split(separator: " ").count, 26)
        XCTAssertTrue(capped?.hasSuffix("…") == true)
    }
}
