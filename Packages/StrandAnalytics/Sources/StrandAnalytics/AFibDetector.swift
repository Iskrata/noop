import Foundation
import WhoopProtocol

/// Fork: irregular-rhythm (possible atrial fibrillation) screen over the strap's beat-to-beat intervals.
///
/// METHOD. Petrėnas, Marozas & Sörnmo 2015, "Low-complexity detection of atrial fibrillation in
/// continuous long-term monitoring" (Comput Biol Med 65:184–191), ported from the reference
/// implementation github.com/tabaraei/LTAF-detection with the paper's parameters:
///   1. 3-point median filter of the R-R series (suppresses isolated ectopic beats);
///   2. forward-backward exponential average of R-R (the rhythm's local mean, α = 0.02);
///   3. irregularity M(n): the share of all beat pairs in the last N = 8 median-filtered intervals that
///      differ by ≥ γ = 30 ms, smoothed the same way and divided by the local mean interval;
///   4. bigeminy measure B(n): how far the median filter moved the last 8 intervals, smoothed;
///   5. decision O(n) = irregularity where B ≥ δ = 2e-4, else B; a beat is irregular when O > η = 0.725.
/// The exponential average starts from the first sample and runs forward then backward (no edge
/// padding), so the Python oracle and this port are the same arithmetic.
///
/// AGGREGATION (fork, after the Fitbit Heart Study's sustained-rhythm rule, Lubitz 2022):
///   - a minute is irregular when > 50% of its beats are, and readable only with ≥ 20 beats while the
///     wrist is still (`MotionStillness`);
///   - an EPISODE is a run of irregular minutes with ≥ 30 of them, bridging ≤ 3 regular minutes;
///     unreadable minutes neither extend nor break a run.
///
/// VALIDATION (2026-09-25, docs/fork/HEART_BREATHING.md). PhysioNet ECG beat annotations with this
/// strap's measured artifact profile injected, 5 noise draws: MIT-BIH AF 15/16 patients with ≥ 30 min
/// of AF flagged, minute sensitivity 91–92% / specificity 97%; Long-Term AF 65–66/67; NSR RR (54 healthy
/// 24 h recordings) 0–1 with a false episode. The owner's own 45 days: 0 episodes.
///
/// A screen, not a diagnosis: atrial flutter with regular conduction is invisible to it, and frequent
/// premature beats are its main false-positive source.
public enum AFibDetector {
    public static let alpha = 0.02
    public static let windowBeats = 8
    public static let gammaSec = 0.03
    public static let delta = 2e-4
    public static let eta = 0.725
    /// Beats further apart (wall clock) than their interval plus this start a new segment.
    public static let maxGapSec = 10.0
    public static let minBeatsPerMinute = 20
    public static let episodeMinMinutes = 30
    public static let maxBridgeMinutes = 3
    public static let rrRangeMs = 300...2000

    public struct Episode: Equatable, Sendable {
        public let startTs: Int
        public let endTs: Int
        public let irregularMinutes: Int
        public init(startTs: Int, endTs: Int, irregularMinutes: Int) {
            self.startTs = startTs; self.endTs = endTs; self.irregularMinutes = irregularMinutes
        }
    }

    /// Per-minute reading: `nil` unreadable, `true` irregular, `false` regular.
    public struct MinuteStates: Equatable, Sendable {
        public let firstMinute: Int
        public let states: [Bool?]
    }

    public struct Summary: Equatable, Sendable {
        public let readableMinutes: Int
        public let irregularMinutes: Int
        public let episodes: [Episode]
    }

    // MARK: - Beat-level detector (the paper)

    static func forwardBackwardEMA(_ x: [Double]) -> [Double] {
        guard let first = x.first else { return [] }
        var y = [Double](repeating: 0, count: x.count)
        var acc = first
        for i in 0..<x.count { acc = (1 - alpha) * acc + alpha * x[i]; y[i] = acc }
        acc = y[y.count - 1]
        for i in stride(from: y.count - 1, through: 0, by: -1) { acc = (1 - alpha) * acc + alpha * y[i]; y[i] = acc }
        return y
    }

    static func median3(_ r: [Double]) -> [Double] {
        guard r.count >= 3 else { return r }
        var out = r
        for i in 1..<(r.count - 1) {
            let a = r[i - 1], b = r[i], c = r[i + 1]
            out[i] = max(min(a, b), min(max(a, b), c))
        }
        return out
    }

    /// Irregular flag per interval for ONE contiguous run of intervals (seconds).
    static func segmentFlags(_ r: [Double]) -> [Bool] {
        let n = r.count
        guard n >= windowBeats + 2 else { return [Bool](repeating: false, count: n) }
        let rm = median3(r)
        let rt = forwardBackwardEMA(r)
        let pairs = Double(windowBeats * (windowBeats - 1)) / 2
        var m = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var count = 0
            for j in 0..<(windowBeats - 1) where i - j >= 0 {
                for k in (j + 1)..<windowBeats where i - k >= 0 {
                    if abs(rm[i - j] - rm[i - k]) >= gammaSec { count += 1 }
                }
            }
            m[i] = Double(count) / pairs
        }
        let mt = forwardBackwardEMA(m)
        var b = [Double](repeating: 0, count: n)
        var sumM = 0.0, sumR = 0.0
        for i in 0..<n {
            sumM += rm[i]; sumR += r[i]
            if i >= windowBeats { sumM -= rm[i - windowBeats]; sumR -= r[i - windowBeats] }
            let q = sumM / sumR - 1
            b[i] = q * q
        }
        let bt = forwardBackwardEMA(b)
        return (0..<n).map { i in
            let o = bt[i] >= delta ? mt[i] / rt[i] : bt[i]
            return o > eta
        }
    }

    /// Irregular flag per beat. `times` are wall-clock seconds, `rrSec` the interval ending at each beat.
    /// The series is split wherever the strap dropped beats for longer than `maxGapSec`.
    public static func beatFlags(times: [Double], rrSec: [Double]) -> [Bool] {
        precondition(times.count == rrSec.count)
        var flags = [Bool](repeating: false, count: rrSec.count)
        var start = 0
        for i in 0...rrSec.count where i == rrSec.count || (i > 0 && times[i] - times[i - 1] - rrSec[i] > maxGapSec) {
            if i > start {
                let f = segmentFlags(Array(rrSec[start..<i]))
                for k in 0..<f.count { flags[start + k] = f[k] }
            }
            start = i
        }
        return flags
    }

    // MARK: - Minutes and episodes (fork aggregation)

    /// `stillMinutes` nil = no motion gate (used by the validation harness on ECG recordings).
    public static func minuteStates(times: [Double], flags: [Bool], stillMinutes: Set<Int>?) -> MinuteStates? {
        guard let t0 = times.first, let tN = times.last else { return nil }
        let first = Int((t0 / 60).rounded(.down)), last = Int((tN / 60).rounded(.down))
        var beats = [Int](repeating: 0, count: last - first + 1)
        var irregular = beats
        for (t, f) in zip(times, flags) {
            let m = Int((t / 60).rounded(.down))
            if let still = stillMinutes, !still.contains(m) { continue }
            beats[m - first] += 1
            if f { irregular[m - first] += 1 }
        }
        let states: [Bool?] = zip(beats, irregular).map { n, a in
            n >= minBeatsPerMinute ? (Double(a) / Double(n) > 0.5) : nil
        }
        return MinuteStates(firstMinute: first, states: states)
    }

    public static func episodes(_ m: MinuteStates) -> [Episode] {
        var out: [Episode] = []
        var start: Int?, end = 0, count = 0, breaks = 0
        func close() {
            if let s = start, count >= episodeMinMinutes {
                out.append(Episode(startTs: (m.firstMinute + s) * 60, endTs: (m.firstMinute + end + 1) * 60,
                                   irregularMinutes: count))
            }
            start = nil; count = 0; breaks = 0
        }
        for (i, s) in m.states.enumerated() {
            if s == true {
                if start == nil { start = i }
                end = i; count += 1; breaks = 0
            } else if s == false, start != nil {
                breaks += 1
                if breaks > maxBridgeMinutes { close() }
            }
        }
        close()
        return out
    }

    // MARK: - App entry point

    /// Beat times from the stored rows: whole-second `ts`, beats sharing a second spread 0.25 s apart in
    /// stored order. Only minute bins and gap splits read these times, so the spread is immaterial.
    public static func beatTimes(_ rr: [RRInterval]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(rr.count)
        var prevTs = Int.min, k = 0
        for r in rr {
            k = r.ts == prevTs ? k + 1 : 0
            prevTs = r.ts
            out.append(Double(r.ts) + 0.25 * Double(k))
        }
        return out
    }

    /// Run the screen over stored beats (ordered by ts, ord) and summarise per day. `dayOf` maps a unix
    /// second to the local day key; an episode belongs to the day it starts.
    public static func analyze(_ rows: [RRInterval], stillMinutes: Set<Int>,
                               dayOf: (Int) -> String) -> [String: Summary] {
        let kept = rows.filter { rrRangeMs.contains($0.rrMs) }
        let times = beatTimes(kept)
        let rrSec = kept.map { Double($0.rrMs) / 1000 }
        guard let m = minuteStates(times: times, flags: beatFlags(times: times, rrSec: rrSec),
                                   stillMinutes: stillMinutes) else { return [:] }
        var readable: [String: Int] = [:], irregular: [String: Int] = [:]
        for (i, s) in m.states.enumerated() {
            guard let s else { continue }
            let day = dayOf((m.firstMinute + i) * 60)
            readable[day, default: 0] += 1
            if s { irregular[day, default: 0] += 1 }
        }
        let byDay = Dictionary(grouping: episodes(m), by: { dayOf($0.startTs) })
        var out: [String: Summary] = [:]
        for day in Set(readable.keys).union(byDay.keys) {
            out[day] = Summary(readableMinutes: readable[day] ?? 0, irregularMinutes: irregular[day] ?? 0,
                               episodes: byDay[day] ?? [])
        }
        return out
    }
}
