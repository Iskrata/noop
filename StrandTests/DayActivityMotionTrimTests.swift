import XCTest
import StrandAnalytics
import WhoopProtocol
@testable import Strand

/// Fork: trimming the Today list's HR-only auto bouts to where the strap moved (`DayActivityMotionTrim`).
/// The shapes are the owner's 2026-09-28 day (resting HR 54, detector floor 84 bpm).
final class DayActivityMotionTrimTests: XCTestCase {
    /// One stretch of minutes at a fixed motion level.
    private enum Stretch {
        case walk(Int)          // 100 steps/min, dynAccel 0.25, 110 bpm
        case sit(Int)           // 0 steps, dynAccel 0.06, 88 bpm (just above the 84 floor)
        case fidget             // one seated minute with a wrist spike: 3 steps, dynAccel 0.2, 88 bpm
        case lift(Int)          // 0 steps, dynAccel 0.2, 115 bpm
        case rest(Int)          // 0 steps, dynAccel 0.05, 100 bpm (between sets)

        var minutes: Int {
            switch self {
            case .walk(let m), .sit(let m), .lift(let m), .rest(let m): return m
            case .fidget: return 1
            }
        }
        var level: (steps: Int, dyn: Double, bpm: Int) {
            switch self {
            case .walk: return (100, 0.25, 110)
            case .sit: return (0, 0.06, 88)
            case .fidget: return (3, 0.2, 88)
            case .lift: return (0, 0.2, 115)
            case .rest: return (0, 0.05, 100)
            }
        }
    }

    private struct Strap {
        var hr: [HRSample] = []
        var steps: [StepSample] = []
        var gravity: [GravitySample] = []
    }

    private let t0 = 1_790_573_640   // 2026-09-28 08:34 local

    /// 1 Hz HR / steps / gravity for `stretches` starting at `start`, with `counter` as the step counter's
    /// starting value. Five seated minutes are added on each side so the median window has context.
    private func strap(_ stretches: [Stretch], from start: Int, counter: Int = 38_000) -> Strap {
        var out = Strap()
        var c = counter
        var ts = start - 5 * 60
        for s in [Stretch.sit(5)] + stretches + [Stretch.sit(5)] {
            let (steps, dyn, bpm) = s.level
            for _ in 0..<s.minutes {
                let base = c
                for sec in 0..<60 {
                    c = base + steps * (sec + 1) / 60
                    out.hr.append(HRSample(ts: ts, bpm: bpm))
                    out.steps.append(StepSample(ts: ts, counter: c))
                    out.gravity.append(GravitySample(ts: ts, x: 0, y: 0, z: 1, dynAccel: dyn))
                    ts += 1
                }
            }
        }
        return out
    }

    private func bout(_ start: Int, minutes: Int) -> DetectedWorkout {
        DetectedWorkout(startSec: start, endSec: start + minutes * 60, avgBpm: 95, peakBpm: 120,
                        durationMin: minutes)
    }

    private func split(_ b: DetectedWorkout, _ s: Strap) -> [DetectedWorkout] {
        DayActivityMotionTrim.split([b], hr: s.hr, steps: s.steps, gravity: s.gravity)
    }

    /// 08:34–09:49 as detected; the walk ended 09:01 and the rest was sitting at 85–93 bpm.
    func testMorningWalkThenSittingTrimsToTheWalk() throws {
        let s = strap([.walk(27), .sit(12), .fidget, .sit(35)], from: t0)
        let pieces = split(bout(t0, minutes: 75), s)
        let piece = try XCTUnwrap(pieces.first)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(piece.startSec, t0)
        XCTAssertEqual(piece.endSec, t0 + 27 * 60)
        XCTAssertEqual(piece.durationMin, 27)
        XCTAssertEqual(piece.avgBpm, 110)
        XCTAssertEqual(piece.peakBpm, 110)
    }

    /// 12:02–14:15 as detected; the only sustained walk was 13:54–14:14, around 2–4 min strolls at 12:02,
    /// 12:28 and 12:36 and long seated stretches with single-minute fidgets.
    func testAfternoonYieldsOnlyTheSustainedWalk() throws {
        let start = t0 + (12 * 60 + 2 - (8 * 60 + 34)) * 60   // 12:02
        let s = strap([.walk(3), .sit(23), .walk(3), .sit(5), .walk(3), .sit(20), .fidget, .sit(30), .fidget,
                       .sit(23), .walk(20), .sit(1)], from: start)
        let pieces = split(bout(start, minutes: 133), s)
        let piece = try XCTUnwrap(pieces.first)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(piece.startSec, start + 112 * 60)   // 13:54
        XCTAssertEqual(piece.endSec, start + 132 * 60)     // 14:14
        XCTAssertEqual(piece.durationMin, 20)
        XCTAssertEqual(piece.avgBpm, 110)
    }

    func testBoutWithoutMotionRowsIsUnchanged() {
        let b = bout(t0, minutes: 75)
        let hr = strap([.walk(27), .sit(48)], from: t0).hr
        XCTAssertEqual(DayActivityMotionTrim.split([b], hr: hr, steps: [], gravity: []), [b])
        // A WHOOP 4.0 has gravity rows but no dynAccel, and no steps: still no motion data.
        let bare = (t0...(t0 + 75 * 60)).map { GravitySample(ts: $0, x: 0, y: 0, z: 1, dynAccel: nil) }
        XCTAssertEqual(DayActivityMotionTrim.split([b], hr: hr, steps: [], gravity: bare), [b])
    }

    func testStrengthSessionWithAThreeMinuteRestStaysWhole() {
        let s = strap([.lift(18), .rest(3), .lift(19)], from: t0)
        let b = bout(t0, minutes: 40)
        XCTAssertEqual(split(b, s), [b])   // unchanged, detector summary kept as-is
    }

    func testLongRestSplitsAndShortPiecesDrop() {
        // 15 min lifting, 8 min sitting, 14 min lifting, 6 min sitting, 5 min lifting.
        let s = strap([.lift(15), .sit(8), .lift(14), .sit(6), .lift(5)], from: t0)
        let pieces = split(bout(t0, minutes: 48), s)
        XCTAssertEqual(pieces.map(\.startSec), [t0, t0 + 23 * 60])
        XCTAssertEqual(pieces.map(\.endSec), [t0 + 15 * 60, t0 + 37 * 60])
        XCTAssertEqual(pieces.map(\.durationMin), [15, 14])
    }

    func testStepCounterResetIsNotMotion() {
        // Seated throughout; the u16 counter wraps/resets mid-bout. A drop must not read as steps.
        var s = strap([.sit(20)], from: t0, counter: 65_500)
        let resetAt = t0 + 10 * 60
        s.steps = s.steps.map { $0.ts >= resetAt ? StepSample(ts: $0.ts, counter: 3) : $0 }
        let minutes = DayActivityMotionTrim.minutes(of: bout(t0, minutes: 20), steps: s.steps, gravity: s.gravity)
        XCTAssertEqual(minutes?.contains(.moving), false)
        XCTAssertTrue(split(bout(t0, minutes: 20), s).isEmpty)
    }

    func testDismissalHidesTheOriginalsPiecesOrJustOnePiece() {
        let s = strap([.walk(15), .sit(10), .walk(14)], from: t0)
        let original = bout(t0, minutes: 39)
        let pieces = split(original, s)
        XCTAssertEqual(pieces.count, 2)

        // Dismissing the ORIGINAL bout (e.g. from the suggestion card) filters it before the split.
        let kept = Repository.undismissedAutoDetectCandidates(
            [original], autoDismissedTokens: ["\(original.startSec):\(original.endSec)"],
            detectedDismissedTokens: [])
        XCTAssertTrue(DayActivityMotionTrim.split(kept, hr: s.hr, steps: s.steps, gravity: s.gravity).isEmpty)

        // Dismissing one PIECE records that piece's own token and leaves its sibling.
        let first = pieces[0]
        let remaining = Repository.undismissedAutoDetectCandidates(
            pieces, autoDismissedTokens: ["\(first.startSec):\(first.endSec)"], detectedDismissedTokens: [])
        XCTAssertEqual(remaining, [pieces[1]])
    }
}
