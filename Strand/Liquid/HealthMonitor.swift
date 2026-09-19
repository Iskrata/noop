import Foundation
import WhoopStore

// MARK: - Health Monitor (fork)
//
// Bevel's "Health Monitor" grid: respiratory rate, resting HR, HRV, SpO2, skin temperature and sleep, each
// read against the wearer's own recent range. This is the pure half: which value a tile shows, the personal
// range it is judged against, and where the marker sits on the tile's vertical range bar.

enum HealthMonitorMetric: String, CaseIterable, Identifiable {
    case respiratory, restingHr, hrv, spo2, skinTemp, sleep
    var id: String { rawValue }

    /// Which way is good: +1 higher is better (HRV, SpO2, sleep), −1 lower is better (resting HR), 0 when
    /// either side of the range is a flag (respiratory rate, skin temperature).
    var betterDirection: Int {
        switch self {
        case .hrv, .spo2, .sleep: return 1
        case .restingHr:          return -1
        case .respiratory, .skinTemp: return 0
        }
    }

    /// This metric's value on one daily row, nil when the row has none.
    func value(_ d: DailyMetric) -> Double? {
        switch self {
        case .respiratory: return d.respRateBpm
        case .restingHr:   return d.restingHr.map(Double.init)
        case .hrv:         return d.avgHrv
        case .spo2:        return d.spo2Pct
        case .skinTemp:    return d.skinTempDevC
        case .sleep:       return d.totalSleepMin
        }
    }
}

/// One tile's reading: the value and how it sits in the wearer's personal range.
struct HealthMonitorReading: Equatable {
    enum Direction: Equatable { case lower, higher, typical }

    let value: Double
    /// Mean and SD of the baseline nights before the value's own day.
    let mean: Double
    let sd: Double
    /// False while there are too few earlier nights to form a range; the tile then shows the value only.
    var hasRange: Bool = true

    /// Standard score against the personal range (0 when the range has no spread).
    var z: Double { sd > 0 ? (value - mean) / sd : 0 }
    /// Inside mean ± 1 SD — Bevel's in-range (blue) vs out-of-range.
    var inRange: Bool { abs(z) <= 1 }

    enum Tone: Equatable { case inRange, better, worse }
    /// Out of range on the metric's good side reads as `better`, not as a warning.
    func tone(_ metric: HealthMonitorMetric) -> Tone {
        guard hasRange, !inRange else { return .inRange }
        let side = value > mean ? 1 : -1
        return metric.betterDirection != 0 && side == metric.betterDirection ? .better : .worse
    }
    var direction: Direction { abs(z) < 0.1 ? .typical : (value < mean ? .lower : .higher) }
    /// Marker height on the range bar, 0 (bottom) … 1 (top); the bar spans mean ± 2.5 SD, so the in-range
    /// band covers 0.3 … 0.7.
    var position: Double { min(1, max(0, (z + 2.5) / 5)) }

    static let bandLow = 0.3, bandHigh = 0.7

    /// The newest row on or before `dayKey` with a value, judged against up to `window` earlier rows. nil
    /// without a value, or when the newest value is older than `maxCarryDays` (a month-old SpO2 import must
    /// read "No data", not pass as today's); `hasRange` false with fewer than `minBaseline` baseline rows.
    static func resolve(_ metric: HealthMonitorMetric, days: [DailyMetric], dayKey: String,
                        window: Int = 30, minBaseline: Int = 5, maxCarryDays: Int = 3) -> HealthMonitorReading? {
        let sorted = days.filter { $0.day <= dayKey }.sorted { $0.day < $1.day }
        guard let idx = sorted.lastIndex(where: { metric.value($0) != nil }),
              let value = metric.value(sorted[idx]),
              daysBetween(sorted[idx].day, dayKey).map({ $0 <= maxCarryDays }) ?? false else { return nil }
        let baseline = sorted[..<idx].compactMap(metric.value).suffix(window)
        guard baseline.count >= minBaseline else {
            return HealthMonitorReading(value: value, mean: value, sd: 0, hasRange: false)
        }
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(baseline.count - 1)
        return HealthMonitorReading(value: value, mean: mean, sd: variance.squareRoot())
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Whole days from `a` to `b` ("yyyy-MM-dd" keys).
    static func daysBetween(_ a: String, _ b: String) -> Int? {
        guard let da = dayFormatter.date(from: a), let db = dayFormatter.date(from: b) else { return nil }
        return Int((db.timeIntervalSince(da) / 86_400).rounded())
    }
}
