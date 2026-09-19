import Foundation
import WhoopProtocol

// StepGait.swift — names a detected bout "walk" or "run" from the strap's OWN per-tick gait class.
//
// The WHOOP 5.0 banks one step record per second with an activity class decoded from @63 (#316:
// 0 still / 1 walk / 2 run). A bout the auto-detector finds is on foot when most of its seconds carry a
// walk/run tick; which of the two wins names it. Unlike `WorkoutTypeClassifier` (a multi-signal
// heuristic still waiting on real labels) this reads only the strap's own verdict, so it answers "on
// foot?" and nothing else — a strength session or a ride returns nil and keeps its generic label.
//
// Checked against the owner's strap (2026-09-19, 5-minute blocks): two outdoor walks read 75–100 %
// walk ticks throughout, a logged strength session 20–35 %, and a still evening under 30 %.
// Display-only: it names a Today row and seeds the save sheet's sport, never a score.

public enum StepGait {
    /// A window needs at least this share of its seconds covered by a classed tick to be judged at all
    /// (a WHOOP 4.0, or a gap in the offload, has none).
    public static let minCoverage = 0.5
    /// Share of the window's seconds that must be walk/run ticks for the bout to count as on foot.
    public static let minOnFootShare = 0.5

    /// `.walk` or `.run` for the bout [start, end] (inclusive), or nil when it isn't clearly on foot or
    /// the steps don't cover it. `steps` may span more than the window; it is filtered here.
    public static func classify(_ steps: [StepSample], start: Int, end: Int) -> CoarseWorkoutClass? {
        guard end > start else { return nil }
        let seconds = Double(end - start + 1)
        var classed = 0, walk = 0, run = 0
        for s in steps where s.ts >= start && s.ts <= end {
            guard let c = s.activityClass else { continue }
            classed += 1
            if c == 1 { walk += 1 } else if c == 2 { run += 1 }
        }
        guard Double(classed) / seconds >= minCoverage,
              Double(walk + run) / seconds >= minOnFootShare else { return nil }
        return run > walk ? .run : .walk
    }
}
