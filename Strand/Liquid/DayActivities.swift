import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Today Activities (fork)
//
// WHOOP lists the day's activities under its three scores: the night's sleep, every logged workout and
// every bout its detector picked up, each with the Effort (strain) it earned. This is the pure half of the
// fork's twin: it merges those sources (plus Apple Health mindful sessions) into one list and scores each
// workout or bout from the strap's own heart rate with the SAME `StrainScorer` inputs the day's Effort
// uses. Display-only — nothing here is persisted.

/// One row of the Today Activities list.
struct DayActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case sleep(CachedSleepSession)
        case workout(WorkoutRow)
        /// A detector bout that isn't saved as a workout (and wasn't dismissed).
        case detected(DetectedWorkout)
        /// An Apple Health mindful session (meditation, breathing).
        case mindful
    }

    let kind: Kind
    let startTs: Int
    let endTs: Int
    /// Effort (0–100) scored from the strap HR inside the activity. For a workout with too little strap HR
    /// it falls back to the row's own stored strain. nil for sleep and mindful sessions, and when neither
    /// exists.
    let effort: Double?

    var id: String {
        switch kind {
        case .sleep: return "sleep-\(startTs)"
        case .workout(let w): return "workout-\(w.startTs)-\(w.sport)"
        case .detected: return "detected-\(startTs)-\(endTs)"
        case .mindful: return "mindful-\(startTs)-\(endTs)"
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

    /// Merge sleep blocks, saved workouts, detector bouts and mindful sessions into one list, newest first
    /// (WHOOP's order), scoring each workout and bout over its own slice of `hr` (time-ordered, covering the
    /// day window).
    static func build(sleeps: [CachedSleepSession], workouts: [WorkoutRow], detected: [DetectedWorkout],
                      mindful: [ClosedRange<Int>] = [], hr: [HRSample], scoring: Scoring) -> [DayActivity] {
        func effort(_ start: Int, _ end: Int, fallback: Double?) -> Double? {
            StrainScorer.strain(hrSlice(hr, from: start, to: end), maxHR: scoring.maxHR,
                                restingHR: scoring.restingHR, method: scoring.method, sex: scoring.sex) ?? fallback
        }
        var rows: [DayActivity] = sleeps.map {
            DayActivity(kind: .sleep($0), startTs: $0.effectiveStartTs, endTs: $0.endTs, effort: nil)
        }
        for w in workouts {
            rows.append(DayActivity(kind: .workout(w), startTs: w.startTs, endTs: w.endTs,
                                    effort: effort(w.startTs, w.endTs, fallback: w.strain)))
        }
        for d in detected {
            rows.append(DayActivity(kind: .detected(d), startTs: d.startSec, endTs: d.endSec,
                                    effort: effort(d.startSec, d.endSec, fallback: nil)))
        }
        for m in mindful {
            rows.append(DayActivity(kind: .mindful, startTs: m.lowerBound, endTs: m.upperBound, effort: nil))
        }
        return rows.sorted { $0.startTs > $1.startTs }
    }

    /// Apple Health mindful sessions in [from, to], or [] where Health isn't available. Installed by the iOS
    /// app's HealthKit bridge at launch; nil on macOS.
    @MainActor static var mindfulSessions: ((_ from: Int, _ to: Int) async -> [ClosedRange<Int>])?

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
