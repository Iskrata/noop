import XCTest
import WhoopStore
@testable import Strand

/// Fork: the WHOOP-fitted Sleep score (`PersonalSleepScore`).
final class PersonalSleepScoreTests: XCTestCase {
    func testPerformanceMatchesTheFittedModel() {
        // A full night (sufficiency capped at 100), 92 % efficient, 80 % consistent.
        XCTAssertEqual(PersonalSleepScore.performance(asleepMin: 540, needMin: 510, efficiencyPct: 92,
                                                      consistencyPct: 80),
                       -24.903 + 37.5 + 29.6 + 48.3, accuracy: 1e-9)
        // 7 h 09 against an 8.6 h need is 83 % sufficient.
        let short = PersonalSleepScore.performance(asleepMin: 429, needMin: 516, efficiencyPct: 92, consistencyPct: 60)
        XCTAssertLessThan(short, 80)
        XCTAssertEqual(PersonalSleepScore.performance(asleepMin: 0, needMin: 500, efficiencyPct: 0, consistencyPct: 0), 0)
    }

    func testConsistencyRewardsSteadyTimingAndNeedsTwoNights() throws {
        XCTAssertNil(PersonalSleepScore.consistency(onsets: [1400], wakes: [420]))
        let steady = try XCTUnwrap(PersonalSleepScore.consistency(onsets: [1400, 1405, 1395, 1400],
                                                                   wakes: [420, 425, 415, 420]))
        let drifting = try XCTUnwrap(PersonalSleepScore.consistency(onsets: [1320, 1380, 1440, 1560],
                                                                     wakes: [390, 420, 480, 600]))
        XCTAssertGreaterThan(steady, 90)
        XCTAssertLessThan(drifting, steady - 30)
    }

    func testCompositeReadsThePublishedNeedAndDayConsistency() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PersonalSleepScoreTests"))
        defaults.removePersistentDomain(forName: "PersonalSleepScoreTests")
        PersonalSleepScore.publish(needHours: 8.5, consistencyByDay: ["2026-09-19": 70], defaults: defaults)
        let day = DailyMetric(day: "2026-09-19", totalSleepMin: 459, efficiency: 0.91, deepMin: nil, remMin: nil,
                              lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                              strain: nil, exerciseCount: nil)
        let score = try XCTUnwrap(PersonalSleepScore.composite(day, defaults: defaults))
        XCTAssertEqual(score, PersonalSleepScore.performance(asleepMin: 459, needMin: 510, efficiencyPct: 91,
                                                             consistencyPct: 70), accuracy: 1e-9)
    }
}
