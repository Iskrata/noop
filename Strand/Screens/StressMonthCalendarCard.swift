import SwiftUI
import StrandDesign

/// Fork: the Stress screen's month view, the same grid as the Today recovery calendar (`MonthHeatCalendar`),
/// each day filled with its band's colour (LOW blue, MEDIUM green, HIGH amber, as the legend under it reads)
/// and its 0-3 value underneath. Bands, not the continuous ramp: the ramp's in-between shades blend to beige
/// and grey-blue, which no longer read as any band. Display-only: the Stress screen has no day to jump to.
/// Reads the model's own `fullTrend`, so its days and values are the ones the Stress Trend chart plots.
struct StressMonthCalendarCard: View {
    let trend: [TrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Stress Calendar", overline: "History")
            NoopCard(tint: StressRamp.calm) {
                MonthHeatCalendar(
                    values: Self.stressByDay(trend),
                    color: Self.bandColor,
                    cellLabel: { StressTrace.formatLevel($0) },
                    summary: { count, mean in
                        String(localized: "\(count) days · average \(StressTrace.formatLevel(mean))")
                    },
                    emptySummary: String(localized: "No stress readings this month"),
                    selected: trend.last?.date ?? Date(),
                    maxDate: Date())
            }
        }
    }

    /// The legend's colour for the band a 0-3 score falls in (`StressBand`'s edges).
    static func bandColor(_ score: Double) -> Color {
        switch StressBand(score: score) {
        case .low:    return StressRamp.calm
        case .medium: return StressRamp.steady
        case .high:   return StressRamp.tense
        }
    }

    /// Day key → that day's 0-3 stress, keyed in the local calendar like the grid.
    static func stressByDay(_ trend: [TrendPoint]) -> [String: Double] {
        var map: [String: Double] = [:]
        for p in trend { map[MonthHeatCalendar.dayParser.string(from: p.date)] = p.value }
        return map
    }
}

/// Fork: the Stress Trend line's smoothing. Day-to-day stress jumps around, so the chart plots a centred
/// rolling mean over the points within ±`halfWindowDays` calendar days of each one (fewer at the ends and
/// across gaps). The half-window grows with the range so a week keeps its shape and a year reads as a trend.
/// The chart's footer (Today, Average) still reads the raw daily values.
enum StressTrendSmoothing {
    static func halfWindowDays(pointCount: Int) -> Int {
        switch pointCount {
        case ..<15: return 1
        case ..<46: return 2
        default: return 3
        }
    }

    /// `points` must be oldest → newest (as `StressModel.fullTrend` is). One sliding window, O(n).
    static func smoothed(_ points: [TrendPoint]) -> [TrendPoint] {
        let half = Double(halfWindowDays(pointCount: points.count)) * 86_400 + 3_600  // +1h absorbs DST shifts
        var lo = 0, hi = 0, sum = 0.0
        return points.map { p in
            while hi < points.count, points[hi].date.timeIntervalSince(p.date) <= half { sum += points[hi].value; hi += 1 }
            while p.date.timeIntervalSince(points[lo].date) > half { sum -= points[lo].value; lo += 1 }
            return TrendPoint(date: p.date, value: sum / Double(hi - lo), segment: p.segment)
        }
    }
}
