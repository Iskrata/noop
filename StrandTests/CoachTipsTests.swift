import XCTest
@testable import Strand
import WhoopStore

/// Fork: the Coach tips' pure pieces — reply → tip lines, and the lab-report / sleep-week prompt digests.
@MainActor
final class CoachTipsTests: XCTestCase {

    func testTipLinesStripBulletsAndCap() {
        let reply = """
        - **Eat** oily fish twice a week to lift HDL.
        • Walk 30 min daily.
        2. Retest lipids in 3 months.

        * Cut alcohol to weekends.
        - One too many.
        """
        XCTAssertEqual(AICoachEngine.tipLines(reply), [
            "Eat oily fish twice a week to lift HDL.",
            "Walk 30 min daily.",
            "Retest lipids in 3 months.",
            "Cut alcohol to weekends.",
        ])
        XCTAssertEqual(AICoachEngine.tipLines(reply, max: 2).count, 2)
    }

    private func row(_ key: String, _ day: String, _ value: Double?, text: String? = nil,
                     unit: String = "mmol/L", ref: String? = nil) -> LabMarkerRow {
        LabMarkerRow(id: key + day, deviceId: "d", markerKey: key, category: "bloodPanel", day: day, takenAt: 0,
                     value: value, valueText: text, unit: unit, source: "ai-scan", note: nil, referenceText: ref)
    }

    func testLabDigestShowsStatusSexRangeAndPrevious() {
        let rows = [
            row("hdl", "2023-07-05", 0.84, ref: "> 1.5"),
            row("hdl", "2025-09-16", 0.97, ref: "жени>1.68 мъже>1.45"),
            row("fasting_glucose", "2025-09-16", 5.38, ref: "2.80 - 6.10"),
            row("custom_urine__ketones", "2025-09-16", nil, text: "neg", ref: "< 1.5"),
        ]
        let digest = AICoachEngine.labReportDigest(day: "2025-09-16", rows: rows, sex: "male") { $0 }
        XCTAssertTrue(digest.hasPrefix("BLOOD TEST REPORT 2025-09-16 (patient: male):"), digest)
        XCTAssertTrue(digest.contains("hdl: 0.97 mmol/L; range жени>1.68 мъже>1.45, BELOW range; previous 0.84 on 2023-07-05"), digest)
        XCTAssertTrue(digest.contains("fasting_glucose: 5.38 mmol/L; range 2.80 - 6.10, in range"), digest)
        XCTAssertTrue(digest.contains("custom_urine__ketones: neg mmol/L; range < 1.5, range not read"), digest)
        XCTAssertFalse(digest.contains("0.84 mmol/L;"), "only the selected report's results are listed")
    }

    func testLabFingerprintChangesWithValues() {
        let a = [row("hdl", "2025-09-16", 0.97)], b = [row("hdl", "2025-09-16", 0.98)]
        XCTAssertNotEqual(AICoachEngine.labFingerprint(day: "2025-09-16", rows: a),
                          AICoachEngine.labFingerprint(day: "2025-09-16", rows: b))
    }

    func testSleepDigestListsNightsAndSpreads() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Sofia")!
        func ts(_ day: Int, _ h: Int, _ m: Int) -> Int {
            Int(cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: m))!.timeIntervalSince1970)
        }
        let sessions = [
            CachedSleepSession(startTs: ts(16, 23, 30), endTs: ts(17, 7, 0), efficiency: 0.9, restingHr: 50, avgHrv: 60, stagesJSON: nil),
            CachedSleepSession(startTs: ts(18, 0, 50), endTs: ts(18, 8, 10), efficiency: 0.88, restingHr: 51, avgHrv: 58, stagesJSON: nil),
            CachedSleepSession(startTs: ts(18, 14, 0), endTs: ts(18, 14, 30), efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil), // nap
        ]
        let days = [
            DailyMetric(day: "2026-09-17", totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 100, lightMin: 230,
                        disturbances: nil, restingHr: 50, avgHrv: 60, recovery: 70, strain: 12, exerciseCount: nil),
            DailyMetric(day: "2026-09-18", totalSleepMin: 390, efficiency: 0.88, deepMin: 80, remMin: 95, lightMin: 215,
                        disturbances: nil, restingHr: 51, avgHrv: 58, recovery: 62, strain: 9, exerciseCount: nil),
        ]
        let digest = AICoachEngine.sleepWeekDigest(days: days, sessions: sessions, needHours: 8.1,
                                                   score: { _ in 80 }, consistency: { $0 == "2026-09-18" ? 71 : nil },
                                                   calendar: cal)
        XCTAssertTrue(digest.contains("SLEEP, LAST 2 NIGHTS (need 8.1h):"), digest)
        XCTAssertTrue(digest.contains("2026-09-17: bed 23:30 wake 07:00, asleep 7.0h, eff 90%"), digest)
        XCTAssertTrue(digest.contains("2026-09-18: bed 00:50 wake 08:10"), digest)          // the nap is not the main sleep
        XCTAssertTrue(digest.contains("consistency 71%"), digest)
        XCTAssertTrue(digest.contains("average asleep 6.8h vs need 8.1h; bedtimes span 1h20; wake times span 1h10"), digest)
    }

    func testOnlyRecentReportsGetTrainingContext() {
        let now = ISO8601DateFormatter().date(from: "2026-09-19T12:00:00Z")!
        XCTAssertTrue(AICoachEngine.isRecentReport("2026-08-01", now: now))
        XCTAssertFalse(AICoachEngine.isRecentReport("2025-09-16", now: now))
        XCTAssertFalse(AICoachEngine.isRecentReport("garbage", now: now))
    }

    func testEmDashesAreRemoved() {
        XCTAssertEqual(AICoachEngine.withoutEmDashes("Charge high at 85% versus recent averages—push hard today"),
                       "Charge high at 85% versus recent averages, push hard today")
        XCTAssertEqual(AICoachEngine.withoutEmDashes("Sleep well — then train – easy"), "Sleep well, then train, easy")
        XCTAssertEqual(AICoachEngine.withoutEmDashes("Aim for 3–5 servings"), "Aim for 3–5 servings")
    }
}
