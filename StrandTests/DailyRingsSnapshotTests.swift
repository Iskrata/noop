import XCTest

/// Fork: the Daily Rings widget's day rule (`WidgetSnapshot.dailyScores(on:)`) and the target band's
/// round trip through the App Group snapshot.
final class DailyRingsSnapshotTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Sofia")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func snap(updated: Date) -> WidgetSnapshot {
        WidgetSnapshot(recovery: 89, bpm: 60, batteryPct: 50, bonded: true, updated: updated,
                       effort: 38, rest: 63, effortTargetLow: 14.0 / 21, effortTargetHigh: 18.0 / 21)
    }

    func testSameDayShowsEverything() {
        let s = snap(updated: at(19, 8)).dailyScores(on: at(19, 23, 59), calendar: cal)
        XCTAssertEqual(s.charge, 89)
        XCTAssertEqual(s.effort, 38)
        XCTAssertEqual(s.rest, 63)
        XCTAssertEqual(s.effortTarget, (14.0 / 21)...(18.0 / 21))
    }

    func testNextDayDropsEffortButCarriesChargeAndRest() {
        let s = snap(updated: at(19, 23, 50)).dailyScores(on: at(20, 0), calendar: cal)
        XCTAssertEqual(s.charge, 89)
        XCTAssertNil(s.effort, "yesterday's finished Effort must not show under today's date")
        XCTAssertEqual(s.rest, 63)
        XCTAssertNil(s.effortTarget)
    }

    func testTwoDaysOldShowsNothing() {
        let s = snap(updated: at(18, 12)).dailyScores(on: at(20, 9), calendar: cal)
        XCTAssertNil(s.charge)
        XCTAssertNil(s.effort)
        XCTAssertNil(s.rest)
    }

    func testTargetBandChangeIsRenderedContent() {
        let a = snap(updated: at(19, 8))
        var b = a
        b.effortTargetLow = 10.0 / 21
        b.effortTargetHigh = 14.0 / 21
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: a, to: b))
        XCTAssertFalse(WidgetSnapshot.renderedContentChanged(from: a, to: a))
    }

    func testOlderSnapshotWithoutBandDecodes() throws {
        let json = #"{"recovery":70,"bonded":true,"updated":0}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)
        XCTAssertNil(decoded.effortTarget)
    }
}
