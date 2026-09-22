import XCTest
import StrandImport
import WhoopStore
@testable import Strand

/// Fork: a night still being recorded waits for its scores (`OpenNight`).
final class OpenNightTests: XCTestCase {
    private let end = 1_790_056_466   // 2026-09-22 08:54, the field night that was scored six times

    private func session(start: Int, end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    private func day(_ key: String, recovery: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: 480, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: nil, recovery: recovery, strain: nil,
                    exerciseCount: nil)
    }

    func testProbeTakesTheLatestNightAndItsDaysHeartRateFrontier() throws {
        let probe = try XCTUnwrap(OpenNight.probe(
            nights: [(day: "2026-09-21", sleeps: [session(start: end - 30 * 3_600, end: end - 23 * 3_600)]),
                     (day: "2026-09-22", sleeps: [session(start: end - 9 * 3_600, end: end)])],
            newestHeartRateByDay: ["2026-09-21": end - 20 * 3_600, "2026-09-22": end]))
        XCTAssertEqual(probe, OpenNight.Probe(wakeDay: "2026-09-22", endTs: end, newestHeartRateTs: end))
        XCTAssertNil(OpenNight.probe(nights: [], newestHeartRateByDay: [:]))
    }

    /// Open while the night stops where the synced data stops; closed once the strap has seen the wearer up
    /// for the margin, or after the hold even without newer data (a strap taken off at wake).
    func testNightClosesAfterTheWearerIsSeenUpOrTheHoldRunsOut() {
        let margin = HealthWriteback.openNightMarginSeconds
        let truncated = OpenNight.Probe(wakeDay: "2026-09-22", endTs: end, newestHeartRateTs: end)
        XCTAssertTrue(truncated.isOpen(now: end + 60))
        let upBriefly = OpenNight.Probe(wakeDay: "2026-09-22", endTs: end, newestHeartRateTs: end + margin - 60)
        XCTAssertTrue(upBriefly.isOpen(now: end + margin))
        let upLongEnough = OpenNight.Probe(wakeDay: "2026-09-22", endTs: end, newestHeartRateTs: end + margin)
        XCTAssertFalse(upLongEnough.isOpen(now: end + margin))
        XCTAssertFalse(truncated.isOpen(now: end + HealthWriteback.openNightMaxHoldSeconds))
    }

    func testPublishedStateIsReadPerDay() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OpenNightTests"))
        defaults.removePersistentDomain(forName: "OpenNightTests")
        let now = Date(timeIntervalSince1970: TimeInterval(end + 300))
        OpenNight.publish(OpenNight.Probe(wakeDay: "2026-09-22", endTs: end, newestHeartRateTs: end), defaults: defaults)
        XCTAssertTrue(OpenNight.isOpen(day: "2026-09-22", now: now, defaults: defaults))
        XCTAssertFalse(OpenNight.isOpen(day: "2026-09-21", now: now, defaults: defaults))
        OpenNight.publish(nil, defaults: defaults)
        XCTAssertFalse(OpenNight.isOpen(day: "2026-09-22", now: now, defaults: defaults))
    }

    /// The widget, wrist and Live Activity carry last night's scored row while today's night is open.
    func testWidgetAnchorCarriesWhileTodaysNightIsOpen() {
        let days = [day("2026-09-21", recovery: 70), day("2026-09-22", recovery: 64)]
        let open = Repository.widgetAnchor(days: days, logicalKey: "2026-09-22", localKey: "2026-09-22",
                                           nightOpen: { $0 == "2026-09-22" })
        XCTAssertEqual(open?.day, "2026-09-21")
        let closed = Repository.widgetAnchor(days: days, logicalKey: "2026-09-22", localKey: "2026-09-22")
        XCTAssertEqual(closed?.day, "2026-09-22")
    }

    func testSleepBannerSaysTheNightIsStillRecording() {
        XCTAssertEqual(resolveSleepFreshness(hasCurrentNight: true, morningReady: true, syncing: false,
                                             calculating: false, syncedSinceDayStart: true, syncFailed: false,
                                             nightOpen: true), .recording)
        XCTAssertNil(resolveSleepFreshness(hasCurrentNight: true, morningReady: true, syncing: false,
                                           calculating: false, syncedSinceDayStart: true, syncFailed: false,
                                           nightOpen: false))
    }
}
