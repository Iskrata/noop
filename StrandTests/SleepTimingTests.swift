import XCTest
@testable import Strand
import WhoopStore

/// Fork: the Sleep timing card's maths — usual window, axis, caption.
final class SleepTimingTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Sofia")!
        return c
    }()

    private func ts(_ day: Int, _ h: Int, _ m: Int) -> Int {
        Int(cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: m))!.timeIntervalSince1970)
    }

    private func night(_ bedDay: Int, _ bh: Int, _ bm: Int, _ wakeDay: Int, _ wh: Int, _ wm: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: ts(bedDay, bh, bm), endTs: ts(wakeDay, wh, wm), efficiency: nil, restingHr: nil,
                           avgHrv: nil, stagesJSON: nil)
    }

    func testUsualIsTheMedianOfPriorMainNightsAcrossMidnight() throws {
        let nights = [
            night(12, 0, 33, 12, 9, 45),
            night(12, 23, 50, 13, 8, 30),            // before midnight still counts as late evening
            night(14, 0, 22, 14, 8, 14),
            night(14, 15, 0, 14, 15, 40),            // nap: too short
            night(15, 0, 4, 15, 9, 23),
        ]
        let last = night(19, 1, 2, 19, 8, 47)
        let usual = try XCTUnwrap(SleepTiming.usual(nights: nights + [last], excluding: last, calendar: cal))
        XCTAssertEqual(SleepTiming.clock(usual.bed), "00:13")   // median of 23:50, 00:04, 00:22, 00:33
        XCTAssertEqual(SleepTiming.clock(usual.wake), "08:57")
        let actual = SleepTiming.window(last, calendar: cal)
        XCTAssertEqual(SleepTiming.caption(actual: actual, usual: usual), "Bed 50 min later · woke on time")
    }

    func testNeedsThreeNights() {
        let last = night(19, 1, 2, 19, 8, 47)
        XCTAssertNil(SleepTiming.usual(nights: [night(14, 0, 22, 14, 8, 14), last], excluding: last, calendar: cal))
    }

    func testCaptionAndAxis() {
        let usual = SleepTiming.Window(bed: 12.5, wake: 21)                 // 00:30 → 09:00
        XCTAssertEqual(SleepTiming.caption(actual: .init(bed: 12.6, wake: 21.1), usual: usual), "Right on your usual schedule")
        XCTAssertEqual(SleepTiming.caption(actual: .init(bed: 11, wake: 19.75), usual: usual),
                       "Bed 1 h 30 min earlier · woke 1 h 15 min earlier")
        XCTAssertEqual(SleepTiming.axis([usual]), 8...24)                    // 20:00 → 12:00
        XCTAssertEqual(SleepTiming.axis([.init(bed: 7.2, wake: 25)]), 6...26)
        XCTAssertEqual(SleepTiming.hourTicks(8...24).map { SleepTiming.clock($0, minutes: false) }, ["20", "00", "04", "08", "12"])
    }
}
