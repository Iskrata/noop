import XCTest
import WhoopStore
@testable import Strand

/// Pins the pure grid + stats helpers behind the Today month recovery calendar (`RecoveryMonthCalendar`).
final class RecoveryMonthCalendarTests: XCTestCase {

    private typealias Cal = RecoveryMonthCalendar

    private func day(_ key: String, recovery: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: recovery, strain: nil, exerciseCount: nil)
    }

    private func date(_ key: String) -> Date { Cal.dayParser.date(from: key)! }

    private func calendar(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = firstWeekday
        return c
    }

    func testOctober2026GridStartsOnThursdayColumn() {
        // 1 Oct 2026 is a Thursday: 3 blanks with Monday first, 4 with Sunday first.
        let monday = Cal.monthCells(monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(monday.prefix(while: { $0 == nil }).count, 3)
        XCTAssertEqual(monday.compactMap { $0 }.count, 31)
        let sunday = Cal.monthCells(monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(sunday.prefix(while: { $0 == nil }).count, 4)
        XCTAssertEqual(Cal.dayParser.string(from: sunday.last!!), "2026-10-31")
    }

    func testFebruaryHasItsOwnLength() {
        let cells = Cal.monthCells(monthStart: date("2026-02-01"), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(cells.compactMap { $0 }.count, 28)
    }

    func testRecoveryMapSkipsUnscoredAndLaterRowWins() {
        let map = Cal.recoveryByDay([day("2026-10-01", recovery: 40), day("2026-10-02", recovery: nil),
                                     day("2026-10-01", recovery: 55)])
        XCTAssertEqual(map, ["2026-10-01": 55])
    }

    func testMonthStatsCountOnlyThatMonth() {
        let map = Cal.recoveryByDay([day("2026-09-30", recovery: 10), day("2026-10-01", recovery: 60),
                                     day("2026-10-15", recovery: 80), day("2026-11-01", recovery: 99)])
        let stats = Cal.monthStats(map, monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.mean, 70, accuracy: 0.001)
        XCTAssertEqual(Cal.monthStats(map, monthStart: date("2026-08-01"), calendar: calendar(firstWeekday: 2)).count, 0)
    }
}
