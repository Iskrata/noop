import Foundation
import StrandAnalytics
import WhoopProtocol

// MARK: - Today Activities: trim auto bouts by strap motion (fork)
//
// `AutoWorkoutDetector` is HR-only on this path (upstream, Kotlin-parity; left untouched). With a low
// resting HR its floor sits where plain sitting can reach: on 2026-09-28 (resting HR 54 → floor 84 bpm)
// the owner sat still at 85–93 bpm with zero steps between walks, and the 90 s dip tolerance plus the
// 5 min merge held the bouts open for up to an hour (08:34–09:49 for a walk that ended 09:01; 12:02–14:15
// for a walk at 13:54–14:14 plus three 2–4 min strolls).
//
// This pass cuts each bout, minute by minute, to where the strap actually moved. DISPLAY-ONLY: it feeds
// the Today Activities list (its rows, their Effort and gait) and nothing else — not the suggestion card,
// not anything persisted, not Apple Health, not a score.
//
// Evidence (the owner's strap, 2026-09-28, per 5 min): mean `dynAccel` sitting 0.05–0.08 (max 0.095),
// walking 0.13–0.37, a strength session 0.08–0.42 and mostly ≥ 0.11; step counter ~40–130 steps/min
// walking, 0 sitting. Per MINUTE, seated fidgets reach 0.10–0.28 for a single minute, so a minute's
// dynAccel is judged by the median of the 5 minutes centred on it: that ignores 1–2 minute spikes and keeps
// a clean edge where a walk starts or stops (a mean would smear a walk's large values into the minutes
// around it). The 0.10 threshold comes from ONE day of ONE wearer's data — it is deliberately
// conservative and meant to be revisited as more days are checked.

enum DayActivityMotionTrim {
    /// A minute whose step counter advanced by at least this much is moving (walking runs ~40–130/min;
    /// seated minutes read 0–8 from arm movement).
    static let minStepsPerMinute = 10
    /// A minute whose centred-median `dynAccel` (g) is at least this is moving.
    static let movingDynAccel = 0.10
    /// Width, in minutes, of the centred median window over per-minute mean `dynAccel`.
    static let dynAccelMedianMinutes = 5
    /// This many consecutive still minutes split a bout (a 3-min rest between sets does not).
    static let splitStillMinutes = 5
    /// A step-counter delta across a gap longer than this is not attributed to a minute (an offload gap).
    static let maxStepGapSec = 120
    /// A piece shorter than the detector's own sustained minimum is dropped.
    static let minPieceSec = Int(AutoWorkoutDetector.minSustainedMin * 60)

    /// Motion class of one minute of a bout.
    enum Minute: Equatable {
        case moving, still
        /// No step row and no dynAccel reading in the minute: neither splits nor anchors a piece.
        case unknown
    }

    /// The gravity read that covers every bout plus the median window's padding, nil for no bouts.
    static func gravityReadSpan(_ bouts: [DetectedWorkout]) -> ClosedRange<Int>? {
        guard let lo = bouts.map(\.startSec).min(), let hi = bouts.map(\.endSec).max() else { return nil }
        let pad = 60 * (dynAccelMedianMinutes / 2)
        return (lo - pad)...(hi + pad + 60)
    }

    /// Every bout trimmed/split by motion, oldest first. `hr`, `steps` and `gravity` are time-ordered and
    /// may span more than the bouts.
    static func split(_ bouts: [DetectedWorkout], hr: [HRSample], steps: [StepSample],
                      gravity: [GravitySample]) -> [DetectedWorkout] {
        bouts.flatMap { split($0, hr: hr, steps: steps, gravity: gravity) }
    }

    /// One bout's pieces. A bout with no motion data at all (no step rows and no dynAccel in its window,
    /// e.g. a WHOOP 4.0) is returned untouched, as is a bout the trim leaves unchanged.
    static func split(_ bout: DetectedWorkout, hr: [HRSample], steps: [StepSample],
                      gravity: [GravitySample]) -> [DetectedWorkout] {
        guard let minutes = minutes(of: bout, steps: steps, gravity: gravity) else { return [bout] }
        var pieces: [DetectedWorkout] = []
        for segment in segments(minutes) {
            guard let first = segment.first(where: { minutes[$0] == .moving }),
                  let last = segment.last(where: { minutes[$0] == .moving }) else { continue }
            let start = bout.startSec + 60 * first
            let end = min(bout.endSec, bout.startSec + 60 * (last + 1))
            guard end - start >= minPieceSec else { continue }
            if start == bout.startSec, end == bout.endSec { return [bout] }
            if let piece = workout(start, end, hr: hr) { pieces.append(piece) }
        }
        return pieces
    }

    /// Per-minute motion over [startSec, endSec] (minute i covers startSec + 60i ..< +60), or nil when the
    /// window has no step row and no dynAccel reading at all.
    static func minutes(of bout: DetectedWorkout, steps: [StepSample], gravity: [GravitySample]) -> [Minute]? {
        let start = bout.startSec, end = bout.endSec
        guard end >= start else { return nil }
        let n = (end - start) / 60 + 1
        func index(_ ts: Int) -> Int { (ts - start) / 60 }

        // Steps: the counter delta lands in the minute of the later sample. A drop is a counter reset or a
        // u16 wrap and adds nothing, and so does a delta across an offload gap.
        var stepCount = [Int](repeating: 0, count: n)
        var hasStepRow = [Bool](repeating: false, count: n)
        var prev: StepSample?
        for s in DayActivities.slice(steps, from: start - maxStepGapSec, to: end, ts: \.ts) {
            if s.ts >= start {
                let i = index(s.ts)
                hasStepRow[i] = true
                if let p = prev, s.counter > p.counter, s.ts - p.ts <= maxStepGapSec {
                    stepCount[i] += s.counter - p.counter
                }
            }
            prev = s
        }

        // dynAccel: the mean per minute over a padded grid, then the centred median per bout minute.
        let pad = dynAccelMedianMinutes / 2
        var sum = [Double](repeating: 0, count: n + 2 * pad)
        var count = [Int](repeating: 0, count: n + 2 * pad)
        let gridStart = start - 60 * pad
        for g in DayActivities.slice(gravity, from: gridStart, to: start + 60 * (n + pad) - 1, ts: \.ts) {
            guard let a = g.dynAccel else { continue }
            let j = (g.ts - gridStart) / 60
            sum[j] += a
            count[j] += 1
        }
        let mean: [Double?] = sum.indices.map { count[$0] > 0 ? sum[$0] / Double(count[$0]) : nil }

        var anyData = false
        let out: [Minute] = (0..<n).map { i in
            let own = mean[i + pad]
            let known = hasStepRow[i] || own != nil
            // Only the bout's own minutes count as "motion data"; the padding is context for the median.
            anyData = anyData || known
            guard known else { return .unknown }
            if stepCount[i] >= minStepsPerMinute { return .moving }
            if own != nil, let m = median(mean[i...(i + 2 * pad)].compactMap { $0 }), m >= movingDynAccel {
                return .moving
            }
            return .still
        }
        return anyData ? out : nil
    }

    /// The minute-index ranges left between runs of at least `splitStillMinutes` still minutes.
    static func segments(_ minutes: [Minute]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var segmentStart = 0, i = 0
        while i < minutes.count {
            guard minutes[i] == .still else { i += 1; continue }
            var j = i
            while j < minutes.count, minutes[j] == .still { j += 1 }
            if j - i >= splitStillMinutes {
                if i > segmentStart { out.append(segmentStart..<i) }
                segmentStart = j
            }
            i = j
        }
        if segmentStart < minutes.count { out.append(segmentStart..<minutes.count) }
        return out
    }

    /// A piece carrying the detector's own summary over its HR (avg rounded, peak, whole minutes); nil
    /// when the strap logged no HR inside it.
    static func workout(_ start: Int, _ end: Int, hr: [HRSample]) -> DetectedWorkout? {
        let bpms = DayActivities.hrSlice(hr, from: start, to: end).map(\.bpm)
        guard let peak = bpms.max() else { return nil }
        let avg = Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded())
        return DetectedWorkout(startSec: start, endSec: end, avgBpm: avg, peakBpm: peak,
                               durationMin: (end - start) / 60)
    }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
