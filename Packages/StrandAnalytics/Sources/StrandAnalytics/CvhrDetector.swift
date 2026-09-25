import Foundation
import WhoopProtocol

/// Fork: sleep-disordered-breathing screen from the cyclic variation of heart rate (CVHR) that apneas
/// leave in the beat train — heart rate slows through the pause and surges when breathing restarts.
///
/// METHOD. Hayano's ACAT (auto-correlated wave detection with adaptive threshold): Hayano et al. 2011
/// Circ Arrhythm Electrophysiol 4:64–72; parameters as restated in Hayano et al. 2020 PLOS One
/// e0237279 and 2022 J Am Heart Assoc (PMC8916582):
///   1. R-R (ms) cleaned of implausible values and of beats > 20% off their 11-beat local median, then
///      resampled at 1 Hz (grid points inside a > 10 s hole in the beat train are unreadable);
///   2. smoothed by 2nd-order polynomial (Savitzky–Golay) fitting;
///   3. dips 10–120 s wide (shoulder to shoulder) with depth/width > 0.7 ms/s;
///   4. adaptive threshold: depth > 40% of the 5th–95th percentile range within 130 s around the dip;
///   5. a dip counts when its ±30 s waveform correlates > 0.4 on average with the 2 preceding and 2
///      following dips, and it sits in a run of 4 consecutive dips whose 3 cycle lengths are 25–130 s
///      with (3 − 2L1/s)(3 − 2L2/s)(3 − 2L3/s) > 0.8, s their mean.
///   The index is counted dips per readable hour.
///
/// The polynomial window is not published; 21 s was chosen on the 35 released Apnea-ECG records and
/// frozen before the 35 withheld ones were scored. Readable time also excludes minutes the wrist moved
/// (`MotionStillness`).
///
/// VALIDATION (2026-09-25, docs/fork/HEART_BREATHING.md), PhysioNet Apnea-ECG with this strap's measured
/// artifact profile injected, 5 noise draws. Withheld set: AUC 0.95–0.98 separating apnea from normal
/// recordings; at the `elevatedIndex` cut-off (fixed on the released set) 12–13/18 apnea recordings
/// flagged, 0/12 normal ones.
/// The owner's 33 nights: 0–1 per hour.
///
/// It cannot tell obstructive from central apnea, under-counts hypopnea-heavy apnea, and periodic leg
/// movements are its main false-positive source.
public enum CvhrDetector {
    public static let smoothHalfWidth = 10
    public static let minDipWidthSec = 10.0, maxDipWidthSec = 120.0
    public static let minDepthPerWidth = 0.7
    public static let envelopeHalfWidth = 65
    public static let minRelativeDepth = 0.4
    public static let minCycleSec = 25.0, maxCycleSec = 130.0
    public static let morphologyHalfWidth = 30
    public static let minMorphologyR = 0.4
    public static let minEquivalence = 0.8
    public static let maxGapSec = 10.0
    public static let rrRangeMs = 300.0...2000.0
    /// A night counts toward the multi-night rule only with this much readable sleep.
    public static let minReadableHours = 4.0
    /// Dips per readable hour at or above which a night is "elevated".
    public static let elevatedIndex = 5.0

    public struct Result: Equatable, Sendable {
        /// Wall-clock seconds of each counted dip.
        public let dipTimes: [Double]
        public let readableHours: Double
        public var index: Double? { readableHours > 0 ? Double(dipTimes.count) / readableHours : nil }
    }

    // MARK: - Steps

    static func clean(times: [Double], rrMs: [Double]) -> (t: [Double], rr: [Double]) {
        var t: [Double] = [], r: [Double] = []
        for (a, b) in zip(times, rrMs) where rrRangeMs.contains(b) { t.append(a); r.append(b) }
        var keepT: [Double] = [], keepR: [Double] = []
        for i in 0..<r.count {
            let window = Array(r[max(0, i - 5)...min(r.count - 1, i + 5)])
            let med = median(window)
            if abs(r[i] - med) <= 0.2 * med { keepT.append(t[i]); keepR.append(r[i]) }
        }
        return (keepT, keepR)
    }

    static func median(_ x: [Double]) -> Double {
        let s = x.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// numpy's default (linear) percentile.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let pos = p / 100 * Double(sorted.count - 1)
        let lo = Int(pos.rounded(.down)), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
    }

    /// 1 Hz grid from ceil(first beat) to floor(last beat); NaN inside a > `maxGapSec` hole.
    static func resample(t: [Double], rr: [Double]) -> (grid: [Double], y: [Double]) {
        guard let first = t.first, let last = t.last, last > first else { return ([], []) }
        var grid: [Double] = [], y: [Double] = []
        var j = 1
        var g = first.rounded(.up)
        while g <= last.rounded(.down) {
            while j < t.count - 1 && t[j] < g { j += 1 }   // first index with t[j] >= g, clipped to [1, n-1]
            let lo = j - 1
            let v: Double
            if t[j] - t[lo] > maxGapSec {
                v = .nan
            } else if g <= t[lo] {
                v = rr[lo]
            } else if g >= t[j] {
                v = rr[j]
            } else {
                v = rr[lo] + (rr[j] - rr[lo]) * (g - t[lo]) / (t[j] - t[lo])
            }
            grid.append(g); y.append(v)
            g += 1
        }
        return (grid, y)
    }

    static func savitzkyGolayQuadratic(_ y: [Double], halfWidth h: Int) -> [Double] {
        let m = Double(2 * h + 1)
        let w = (-h...h).map { k -> Double in
            let kk = Double(k * k)
            return 3 * (3 * m * m - 7 - 20 * kk) / (4 * m * (m * m - 4))
        }
        var out = [Double](repeating: .nan, count: y.count)
        guard y.count > 2 * h else { return out }
        for i in h..<(y.count - h) {
            var acc = 0.0, ok = true
            for (k, wk) in w.enumerated() {
                let v = y[i - h + k]
                if v.isNaN { ok = false; break }
                acc += wk * v
            }
            if ok { out[i] = acc }
        }
        return out
    }

    static func pearson(_ a: ArraySlice<Double>, _ b: ArraySlice<Double>) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for (x, y) in zip(a, b) { sab += (x - ma) * (y - mb); saa += (x - ma) * (x - ma); sbb += (y - mb) * (y - mb) }
        return sab / (saa * sbb).squareRoot()
    }

    // MARK: - Detector

    /// `still(t)` says whether wall-clock second `t` is readable; nil reads every second.
    public static func detect(times: [Double], rrMs: [Double], still: ((Double) -> Bool)? = nil) -> Result {
        let c = clean(times: times, rrMs: rrMs)
        guard c.rr.count >= 200 else { return Result(dipTimes: [], readableHours: 0) }
        var (grid, y) = resample(t: c.t, rr: c.rr)
        if let still { for i in 0..<grid.count where !still(grid[i]) { y[i] = .nan } }
        let s = savitzkyGolayQuadratic(y, halfWidth: smoothHalfWidth)
        let readableHours = Double(s.filter { !$0.isNaN }.count) / 3600

        var mins: [Int] = [], maxs: [Int] = []
        if s.count >= 3 {
            for i in 1..<(s.count - 1) {
                let a = s[i - 1], b = s[i], cc = s[i + 1]
                if a.isNaN || b.isNaN || cc.isNaN { continue }
                if b < a && b <= cc { mins.append(i) } else if b > a && b >= cc { maxs.append(i) }
            }
        }

        var candidates: [Int] = []
        var mx = 0
        for m in mins {
            while mx < maxs.count && maxs[mx] < m { mx += 1 }
            guard mx > 0, mx < maxs.count else { continue }
            let l = maxs[mx - 1], r = maxs[mx]
            if s[l...r].contains(where: { $0.isNaN }) { continue }
            let width = Double(r - l)
            guard width >= minDipWidthSec, width <= maxDipWidthSec else { continue }
            let depth = min(s[l], s[r]) - s[m]
            guard depth / width > minDepthPerWidth else { continue }
            let env = y[max(0, m - envelopeHalfWidth)...min(y.count - 1, m + envelopeHalfWidth)]
                .filter { !$0.isNaN }.sorted()
            guard env.count >= 10 else { continue }
            let range = percentile(env, 95) - percentile(env, 5)
            guard range > 0, depth >= minRelativeDepth * range else { continue }
            candidates.append(m)
        }

        let segments: [ArraySlice<Double>?] = candidates.map { c in
            let a = c - morphologyHalfWidth, b = c + morphologyHalfWidth + 1
            guard a >= 0, b <= s.count else { return nil }
            let seg = s[a..<b]
            return seg.contains(where: { $0.isNaN }) ? nil : seg
        }
        let ct = candidates.map { Double($0) }
        var dips: [Double] = []
        for i in 0..<candidates.count {
            var rs: [Double] = []
            for j in [i - 2, i - 1, i + 1, i + 2] where j >= 0 && j < candidates.count {
                guard let a = segments[i], let b = segments[j] else { continue }
                let r = pearson(a, b)
                if !r.isNaN { rs.append(r) }
            }
            guard rs.count >= 2, rs.reduce(0, +) / Double(rs.count) > minMorphologyR else { continue }
            var cyclic = false
            for st in (i - 3)...i where st >= 0 && st + 3 < candidates.count {
                let l = (0..<3).map { ct[st + $0 + 1] - ct[st + $0] }
                guard l.allSatisfy({ $0 >= minCycleSec && $0 <= maxCycleSec }) else { continue }
                let mean = l.reduce(0, +) / 3
                if l.reduce(1.0, { $0 * (3 - 2 * $1 / mean) }) > minEquivalence { cyclic = true; break }
            }
            if cyclic { dips.append(grid[candidates[i]]) }
        }
        return Result(dipTimes: dips, readableHours: readableHours)
    }

    /// App entry point: one sleep session's stored beats plus its still minutes.
    public static func analyze(_ rows: [RRInterval], stillMinutes: Set<Int>) -> Result {
        let times = AFibDetector.beatTimes(rows)
        return detect(times: times, rrMs: rows.map { Double($0.rrMs) }) { t in
            stillMinutes.contains(Int((t / 60).rounded(.down)))
        }
    }
}
