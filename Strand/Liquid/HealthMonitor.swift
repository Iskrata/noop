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
    /// Inside mean ± 1 SD — Bevel's in-range (blue) vs out-of-range (orange).
    var inRange: Bool { abs(z) <= 1 }
    var direction: Direction { abs(z) < 0.1 ? .typical : (value < mean ? .lower : .higher) }
    /// Marker height on the range bar, 0 (bottom) … 1 (top); the bar spans mean ± 2.5 SD, so the in-range
    /// band covers 0.3 … 0.7.
    var position: Double { min(1, max(0, (z + 2.5) / 5)) }

    static let bandLow = 0.3, bandHigh = 0.7

    /// The newest row on or before `dayKey` with a value, judged against up to `window` earlier rows. nil
    /// without a value; `hasRange` false with fewer than `minBaseline` baseline rows (no honest range).
    static func resolve(_ metric: HealthMonitorMetric, days: [DailyMetric], dayKey: String,
                        window: Int = 30, minBaseline: Int = 5) -> HealthMonitorReading? {
        let sorted = days.filter { $0.day <= dayKey }.sorted { $0.day < $1.day }
        guard let idx = sorted.lastIndex(where: { metric.value($0) != nil }),
              let value = metric.value(sorted[idx]) else { return nil }
        let baseline = sorted[..<idx].compactMap(metric.value).suffix(window)
        guard baseline.count >= minBaseline else {
            return HealthMonitorReading(value: value, mean: value, sd: 0, hasRange: false)
        }
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(baseline.count - 1)
        return HealthMonitorReading(value: value, mean: mean, sd: variance.squareRoot())
    }
}
