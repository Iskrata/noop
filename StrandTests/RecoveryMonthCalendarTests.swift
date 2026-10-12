import XCTest
import WhoopStore
import StrandDesign
@testable import Strand

/// Pins the pure grid + stats helpers behind the month calendars (`MonthHeatCalendar`) and the recovery map
/// the Today one reads (`RecoveryMonthCalendar`).
final class RecoveryMonthCalendarTests: XCTestCase {

    private typealias Cal = RecoveryMonthCalendar
    private typealias Grid = MonthHeatCalendar

    private func day(_ key: String, recovery: Double?) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil,
                    recovery: recovery, strain: nil, exerciseCount: nil)
    }

    private func date(_ key: String) -> Date { Grid.dayParser.date(from: key)! }

    private func calendar(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.firstWeekday = firstWeekday
        return c
    }

    func testOctober2026GridStartsOnThursdayColumn() {
        // 1 Oct 2026 is a Thursday: 3 blanks with Monday first, 4 with Sunday first.
        let monday = Grid.monthCells(monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(monday.prefix(while: { $0 == nil }).count, 3)
        XCTAssertEqual(monday.compactMap { $0 }.count, 31)
        let sunday = Grid.monthCells(monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(sunday.prefix(while: { $0 == nil }).count, 4)
        XCTAssertEqual(Grid.dayParser.string(from: sunday.last!!), "2026-10-31")
    }

    func testFebruaryHasItsOwnLength() {
        let cells = Grid.monthCells(monthStart: date("2026-02-01"), calendar: calendar(firstWeekday: 2))
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
        let stats = Grid.monthStats(map, monthStart: date("2026-10-01"), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.mean, 70, accuracy: 0.001)
        XCTAssertEqual(Grid.monthStats(map, monthStart: date("2026-08-01"), calendar: calendar(firstWeekday: 2)).count, 0)
    }
}

/// Pins the Stress Trend line's rolling mean and the stress calendar's day keying.
final class StressTrendSmoothingTests: XCTestCase {

    private func pt(_ day: Int, _ v: Double) -> TrendPoint {
        TrendPoint(date: MonthHeatCalendar.dayParser.date(from: String(format: "2026-09-%02d", day))!, value: v)
    }

    func testShortRangeAveragesNeighboursAndShrinksAtTheEnds() {
        let out = StressTrendSmoothing.smoothed([pt(1, 0), pt(2, 3), pt(3, 0), pt(4, 3)]).map(\.value)
        XCTAssertEqual(out, [1.5, 1.0, 2.0, 1.5])
    }

    func testGapsAreNotBridged() {
        // Day 10 is more than a day from day 1, so neither borrows from the other.
        let out = StressTrendSmoothing.smoothed([pt(1, 1), pt(10, 3)]).map(\.value)
        XCTAssertEqual(out, [1, 3])
    }

    func testWindowGrowsWithRange() {
        XCTAssertEqual(StressTrendSmoothing.halfWindowDays(pointCount: 7), 1)
        XCTAssertEqual(StressTrendSmoothing.halfWindowDays(pointCount: 30), 2)
        XCTAssertEqual(StressTrendSmoothing.halfWindowDays(pointCount: 365), 3)
    }

    func testCalendarKeysEachPointByItsLocalDay() {
        XCTAssertEqual(StressMonthCalendarCard.stressByDay([pt(3, 2.4)]), ["2026-09-03": 2.4])
    }
}
