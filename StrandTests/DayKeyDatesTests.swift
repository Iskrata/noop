import XCTest
@testable import Strand

/// `DayKeyDates` memoizes what the Trends and metric-detail screens used to parse / format per row per
/// render, so it has to hand back exactly what a fresh formatter would, on the first call and every
/// call after it.
final class DayKeyDatesTests: XCTestCase {
    private func freshParser() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    func testParseMatchesAFreshFormatterOnFirstAndRepeatedCalls() {
        let keys = ["2024-02-29", "2025-12-31", "2026-01-01", "1999-07-04", "2026-09-19",
                    "", "not-a-day", "2026-13-01", "2026-9-1", "2026-09-19T00:00"]
        let reference = freshParser()
        for key in keys {
            let expected = reference.date(from: key)
            XCTAssertEqual(DayKeyDates.utc(key), expected, "first call for \(key)")
            XCTAssertEqual(DayKeyDates.utc(key), expected, "memoized call for \(key)")
        }
    }

    func testLabelMatchesAFreshFormatterPerLocale() throws {
        let date = try XCTUnwrap(freshParser().date(from: "2026-03-07"))
        for id in ["en_US", "de_DE", "bg_BG", "ja_JP"] {
            let locale = Locale(identifier: id)
            for format in ["d MMM", "d MMM yyyy", "MMMM yyyy"] {
                let f = DateFormatter()
                f.locale = locale
                f.timeZone = TimeZone(identifier: "UTC")
                f.dateFormat = format
                XCTAssertEqual(DayKeyDates.label(date, format: format, locale: locale), f.string(from: date))
                XCTAssertEqual(DayKeyDates.label(date, format: format, locale: locale), f.string(from: date))
            }
        }
    }
}
