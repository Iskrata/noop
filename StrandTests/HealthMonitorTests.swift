import XCTest
import WhoopStore
@testable import Strand

/// Fork: the Health Monitor tiles' personal-range read (`HealthMonitorReading`).
final class HealthMonitorTests: XCTestCase {
    private func day(_ n: Int, hrv: Double?) -> DailyMetric {
        DailyMetric(day: String(format: "2026-09-%02d", n), totalSleepMin: nil, efficiency: nil, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testValueIsJudgedAgainstEarlierNightsOnly() throws {
        var days = (1...10).map { day($0, hrv: $0.isMultiple(of: 2) ? 90 : 100) }   // mean 95, sd ≈ 5.27
        days.append(day(11, hrv: 80))
        let r = try XCTUnwrap(HealthMonitorReading.resolve(.hrv, days: days, dayKey: "2026-09-11"))
        XCTAssertEqual(r.value, 80)
        XCTAssertEqual(r.mean, 95, accuracy: 1e-9)
        XCTAssertFalse(r.inRange)
        XCTAssertEqual(r.direction, .lower)
        XCTAssertLessThan(r.position, HealthMonitorReading.bandLow)
    }

    func testCarriesTheLatestValueAndNeedsABaselineForARange() throws {
        let days = [day(1, hrv: 90), day(2, hrv: 95), day(3, hrv: nil)]
        let r = try XCTUnwrap(HealthMonitorReading.resolve(.hrv, days: days, dayKey: "2026-09-03"))
        XCTAssertEqual(r.value, 95)
        XCTAssertFalse(r.hasRange)
        XCTAssertNil(HealthMonitorReading.resolve(.spo2, days: days, dayKey: "2026-09-03"))
    }
}
