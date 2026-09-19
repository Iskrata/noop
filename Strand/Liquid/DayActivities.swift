import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Today Activities (fork)
//
// WHOOP lists the day's activities under its three scores: the night's sleep, every logged workout and
// every bout its detector picked up, each with the Effort (strain) it earned. This is the pure half of the
// fork's twin: it merges the three sources into one chronological list and scores each activity from the
// strap's own heart rate with the SAME `StrainScorer` inputs the day's Effort uses, so an activity's number
// and its share of the day are on one scale. Display-only — nothing here is persisted.

/// One row of the Today Activities list.
struct DayActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case sleep(CachedSleepSession)
        case workout(WorkoutRow)
        /// A detector bout that isn't saved as a workout (and wasn't dismissed).
        case detected(DetectedWorkout)
    }

    let kind: Kind
    let startTs: Int
    let endTs: Int
    /// Effort (0–100) scored from the strap HR inside the activity. For a workout with too little strap HR
    /// it falls back to the row's own stored strain. nil for sleep, and when neither exists.
    let effort: Double?
    /// This activity's fraction of the day's Effort LOAD (see `DayActivities.loadShare`). nil when either
    /// side is missing.
    let share: Double?

    var id: String {
        switch kind {
        case .sleep: return "sleep-\(startTs)"
        case .workout(let w): return "workout-\(w.startTs)-\(w.sport)"
        case .detected: return "detected-\(startTs)-\(endTs)"
        }
    }
}

enum DayActivities {
    /// Scoring inputs shared by every activity of the day — the ones `LiquidTodayView.load()` passes to
    /// `StrainScorer.strain` for the day's live Effort.
    struct Scoring {
        let maxHR: Double?
        let restingHR: Double
        let method: StrainScorer.Method
        let sex: String
    }

    /// Merge sleep blocks, saved workouts and detector bouts into one list, newest first (WHOOP's order),
    /// scoring each non-sleep activity over its own slice of `hr` (time-ordered, covering the day window).
    static func build(sleeps: [CachedSleepSession], workouts: [WorkoutRow], detected: [DetectedWorkout],
                      hr: [HRSample], dayEffort: Double?, scoring: Scoring) -> [DayActivity] {
        func scored(_ start: Int, _ end: Int, fallback: Double?) -> (Double?, Double?) {
            let slice = hrSlice(hr, from: start, to: end)
            let effort = StrainScorer.strain(slice, maxHR: scoring.maxHR, restingHR: scoring.restingHR,
                                             method: scoring.method, sex: scoring.sex) ?? fallback
            let share = effort.flatMap { e in
                dayEffort.flatMap { loadShare(activityEffort: e, dayEffort: $0, method: scoring.method, sex: scoring.sex) }
            }
            return (effort, share)
        }
        var rows: [DayActivity] = sleeps.map {
            DayActivity(kind: .sleep($0), startTs: $0.effectiveStartTs, endTs: $0.endTs, effort: nil, share: nil)
        }
        for w in workouts {
            let (effort, share) = scored(w.startTs, w.endTs, fallback: w.strain)
            rows.append(DayActivity(kind: .workout(w), startTs: w.startTs, endTs: w.endTs, effort: effort, share: share))
        }
        for d in detected {
            let (effort, share) = scored(d.startSec, d.endSec, fallback: nil)
            rows.append(DayActivity(kind: .detected(d), startTs: d.startSec, endTs: d.endSec, effort: effort, share: share))
        }
        return rows.sorted { $0.startTs > $1.startTs }
    }

    /// The fraction of the day's Effort LOAD an activity accounts for. Effort is a log map of load
    /// (`StrainScorer.trimpToStrain`: effort = 100·ln(load+1)/ln D), so the two Efforts are mapped back to
    /// load before dividing — dividing the Efforts themselves would overstate every short activity. Capped
    /// at 1 (an activity scored from a denser slice can edge past a day scored with the stored row).
    static func loadShare(activityEffort: Double, dayEffort: Double, method: StrainScorer.Method,
                          sex: String) -> Double? {
        let lnD = log(StrainScorer.logMapDenominator(method: method, sex: sex))
        guard lnD > 0, dayEffort > 0 else { return nil }
        func load(_ effort: Double) -> Double { exp(effort * lnD / StrainScorer.maxStrain) - 1 }
        let day = load(dayEffort)
        guard day > 0 else { return nil }
        return min(1, max(0, load(activityEffort) / day))
    }

    /// The samples with `from <= ts <= to` from a time-ordered stream, by binary search.
    static func hrSlice(_ hr: [HRSample], from: Int, to: Int) -> [HRSample] {
        guard to >= from else { return [] }
        var lo = 0, hi = hr.count
        while lo < hi { let mid = (lo + hi) / 2; if hr[mid].ts < from { lo = mid + 1 } else { hi = mid } }
        var end = lo
        while end < hr.count, hr[end].ts <= to { end += 1 }
        return Array(hr[lo..<end])
    }

    /// The sleep blocks that belong to a day window: every block that ENDS inside (from, to]. The main night
    /// ends after the window opens in both day-cycle modes (calendar midnight, or the night's own onset),
    /// and a daytime nap ends inside it too.
    static func sleepsEnding(in blocks: [CachedSleepSession], from: Int, to: Int) -> [CachedSleepSession] {
        blocks.filter { $0.endTs > from && $0.endTs <= to }
    }
}
