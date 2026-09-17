import Foundation
import WhoopStore
import StrandAnalytics

/// The last week's bedtimes and wake times, for the Sleep Schedule screen: how regular the sleep window is,
/// which a single consistency percentage hides.
struct SleepSchedule: Equatable {
    struct Night: Equatable {
        /// Local "yyyy-MM-dd" of the wake.
        let wakeDay: String
        /// Unix seconds: the main night's bridged onset and wake.
        let bedtime: Int
        let wake: Int
    }

    /// Oldest first, at most one per wake day, only days that had a night.
    let nights: [Night]
    /// Local time of day as minutes after noon (0...1440), so a window crossing midnight averages correctly.
    let averageBedtimeMin: Double?
    let averageWakeMin: Double?
    /// Population standard deviation of bedtime / wake across `nights`, in minutes. Nil under two nights.
    let bedtimeSpreadMin: Double?
    let wakeSpreadMin: Double?

    /// How many wake days back the schedule covers, today included.
    static let days = 7

    /// Build from stored sessions. Each wake day takes its MAIN night (`SleepStageTotals.mainNightIndex`, the
    /// selector the Sleep tab's hero uses, so a nap never stands in for the night) widened to its bridged group
    /// (`bridgedNightGroups`), so a night split by a brief wake keeps its real onset.
    static func build(sessions: [CachedSleepSession], now: Date, offsetSec: Int,
                      habitualMidsleepSec: Int? = nil) -> SleepSchedule {
        let blocks = sessions.map { SleepStageTotals.NightBlock(start: $0.effectiveStartTs, end: $0.endTs) }
        let groups = SleepStageTotals.bridgedNightGroups(blocks, offsetSec: offsetSec)
        let today = localDay(Int(now.timeIntervalSince1970), offsetSec)
        var nights: [Night] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            let day = today - back
            let indices = blocks.indices.filter { localDay(blocks[$0].end, offsetSec) == day && blocks[$0].end > blocks[$0].start }
            guard let pick = SleepStageTotals.mainNightIndex(indices.map { blocks[$0] }, offsetSec: offsetSec,
                                                             habitualMidsleepSec: habitualMidsleepSec) else { continue }
            let main = indices[pick]
            let group = groups.first { $0.indices.contains(main) }?.indices ?? [main]
            nights.append(Night(wakeDay: AnalyticsEngine.dayString(day * 86_400, offsetSec: 0),
                                bedtime: group.map { blocks[$0].start }.min()!,
                                wake: group.map { blocks[$0].end }.max()!))
        }
        let bed = nights.map { minutesAfterNoon($0.bedtime, offsetSec) }
        let wake = nights.map { minutesAfterNoon($0.wake, offsetSec) }
        return SleepSchedule(nights: nights, averageBedtimeMin: mean(bed), averageWakeMin: mean(wake),
                             bedtimeSpreadMin: spread(bed), wakeSpreadMin: spread(wake))
    }

    /// Local time of day as minutes after noon: 12:00 → 0, 00:00 → 720, 11:59 → 1439.
    static func minutesAfterNoon(_ ts: Int, _ offsetSec: Int) -> Double {
        let secOfDay = ((ts + offsetSec) % 86_400 + 86_400) % 86_400
        return Double((secOfDay + 43_200) % 86_400) / 60.0
    }

    /// "HH:mm" for minutes after noon.
    static func clockLabel(minutesAfterNoon: Double) -> String {
        let total = (Int(minutesAfterNoon.rounded()) + 720) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func localDay(_ ts: Int, _ offsetSec: Int) -> Int {
        Int((Double(ts + offsetSec) / 86_400).rounded(.down))
    }

    private static func mean(_ v: [Double]) -> Double? {
        v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private static func spread(_ v: [Double]) -> Double? {
        guard v.count >= 2, let m = mean(v) else { return nil }
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    }
}
