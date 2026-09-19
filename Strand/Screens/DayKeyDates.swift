import Foundation

/// `yyyy-MM-dd` day keys → the UTC-midnight `Date` the trend charts plot them at, memoized; and the
/// localized UTC day labels drawn from them.
///
/// A `DateFormatter` parse costs ~15 µs, and the Trends body parses one per banked day per metric on every
/// evaluation: five metric windows plus the year strip came to ~2,600 parses (~40 ms on an M-series Mac,
/// a year of history on ALL) for each range tap or week step. The keys are a small closed set (one per
/// calendar day), so each is parsed once per process and read back from a dictionary afterwards. The
/// parser is the exact one every caller used before, so the dates are identical; a key it rejects stays
/// nil. Locked, because the formatter and the table are shared by every caller.
enum DayKeyDates {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let lock = NSLock()
    private static var memo: [String: Date?] = [:]

    static func utc(_ day: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = memo[day] { return hit }
        let parsed = parser.date(from: day)
        memo[day] = parsed
        return parsed
    }

    private static var labelFormatters: [String: DateFormatter] = [:]

    /// `date` as a calendar-day label in UTC (the zone day keys are banked in), in `locale` and `format`.
    ///
    /// Building a `DateFormatter` costs far more than using one, and the metric detail's readings table
    /// built one per row per render: 409 rows took ~24 ms on an M-series Mac on ALL. One formatter is kept
    /// per (format, locale) pair, so a region change still gets a fresh one.
    static func label(_ date: Date, format: String, locale: Locale = AppLanguage.activeLocale) -> String {
        let key = format + "|" + locale.identifier
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = labelFormatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            labelFormatters[key] = formatter
        }
        return formatter.string(from: date)
    }
}
