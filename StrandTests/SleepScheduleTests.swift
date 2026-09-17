import XCTest
import WhoopStore
@testable import Strand

final class SleepScheduleTests: XCTestCase {

    /// 2026-09-17 00:00 UTC; tests run with a zero offset so local == UTC.
    private let midnight = 1_789_603_200
    private var now: Date { Date(timeIntervalSince1970: TimeInterval(midnight + 10 * 3600)) }

    /// A session from `bedHour` the evening before wake day `back` (0 = today) to `wakeHour` that day.
    private func night(back: Int, bed: Double, wake: Double) -> CachedSleepSession {
        let day = midnight - back * 86_400
        let start = day + Int((bed - 24) * 3600)
        return CachedSleepSession(startTs: start, endTs: day + Int(wake * 3600), efficiency: nil,
                                  restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    func testBedtimesEitherSideOfMidnightAverageToMidnight() {
        let s = SleepSchedule.build(sessions: [night(back: 1, bed: 23.5, wake: 7), night(back: 0, bed: 24.5, wake: 7)],
                                    now: now, offsetSec: 0)
        XCTAssertEqual(s.nights.count, 2)
        XCTAssertEqual(SleepSchedule.clockLabel(minutesAfterNoon: s.averageBedtimeMin!), "00:00")
        XCTAssertEqual(s.bedtimeSpreadMin!, 30, accuracy: 0.01)
        XCTAssertEqual(s.wakeSpreadMin!, 0, accuracy: 0.01)
    }

    func testANapNeverStandsInForTheNight() {
        let nap = CachedSleepSession(startTs: midnight + 14 * 3600, endTs: midnight + 15 * 3600, efficiency: nil,
                                     restingHr: nil, avgHrv: nil, stagesJSON: nil)
        let s = SleepSchedule.build(sessions: [night(back: 0, bed: 23, wake: 7), nap],
                                    now: Date(timeIntervalSince1970: TimeInterval(midnight + 16 * 3600)), offsetSec: 0)
        XCTAssertEqual(s.nights.count, 1)
        XCTAssertEqual(s.nights[0].wake, midnight + 7 * 3600)
    }

    func testOnlyTheLastSevenWakeDaysCount() {
        let sessions = (0..<10).map { night(back: $0, bed: 23, wake: 7) }
        let s = SleepSchedule.build(sessions: sessions, now: now, offsetSec: 0)
        XCTAssertEqual(s.nights.count, 7)
        XCTAssertEqual(s.nights.last?.wakeDay, "2026-09-17")
        XCTAssertEqual(s.nights.first?.wakeDay, "2026-09-11")
    }

    func testOneNightHasAveragesButNoSpread() {
        let s = SleepSchedule.build(sessions: [night(back: 0, bed: 22, wake: 6)], now: now, offsetSec: 0)
        XCTAssertEqual(SleepSchedule.clockLabel(minutesAfterNoon: s.averageBedtimeMin!), "22:00")
        XCTAssertEqual(SleepSchedule.clockLabel(minutesAfterNoon: s.averageWakeMin!), "06:00")
        XCTAssertNil(s.bedtimeSpreadMin)
    }
}
