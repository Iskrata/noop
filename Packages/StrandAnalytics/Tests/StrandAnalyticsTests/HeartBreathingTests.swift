import XCTest
import WhoopProtocol
@testable import StrandAnalytics

/// Fork: irregular-rhythm (`AFibDetector`) and breathing-disturbance (`CvhrDetector`) screens.
///
/// The golden numbers are the stdout of the Python reference used for validation
/// (docs/fork/HEART_BREATHING.md, `golden.py` there), run over the SAME deterministic synthetic
/// signals built below with the same LCG. The Swift port also matched that reference exactly on real
/// data (the owner's 14 days and 14 nights, four noisy PhysioNet records) — these tests keep it there.
final class HeartBreathingTests: XCTestCase {

    private struct LCG {
        var x: UInt64
        mutating func u() -> Double {
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return Double(x >> 11) / Double(UInt64(1) << 53)
        }
    }

    private static let t0 = 1_790_000_040.0

    private func build(_ parts: [[Double]]) -> (t: [Double], rr: [Double]) {
        var t = Self.t0, ts: [Double] = [], rr: [Double] = []
        for p in parts { for r in p { t += r; ts.append(t); rr.append(r) } }
        return (ts, rr)
    }

    private func generate(minutes: Double, _ next: (Int, Double) -> Double) -> [Double] {
        var out: [Double] = [], acc = 0.0, i = 0
        while acc < minutes * 60 { let r = next(i, acc); out.append(r); acc += r; i += 1 }
        return out
    }

    private func sinus(_ minutes: Double) -> [Double] {
        generate(minutes: minutes) { _, acc in 0.9 + 0.04 * sin(2 * Double.pi * acc / 4) }
    }

    private func irregular(_ minutes: Double, seed: UInt64) -> [Double] {
        var g = LCG(x: seed)
        return generate(minutes: minutes) { _, _ in 0.45 + 0.6 * g.u() }
    }

    private func bigeminy(_ minutes: Double) -> [Double] {
        generate(minutes: minutes) { i, _ in i % 2 == 0 ? 0.6 : 1.1 }
    }

    // MARK: - Irregular rhythm

    func testSustainedIrregularRunIsOneEpisodeMatchingReference() {
        let (t, rr) = build([sinus(30), irregular(60, seed: 42), sinus(30)])
        let flags = AFibDetector.beatFlags(times: t, rrSec: rr)
        let m = AFibDetector.minuteStates(times: t, flags: flags, stillMinutes: nil)!
        XCTAssertEqual(flags.filter { $0 }.count, 4786)
        XCTAssertEqual(m.states.compactMap { $0 }.count, 120)
        XCTAssertEqual(m.states.filter { $0 == true }.count, 60)
        XCTAssertEqual(AFibDetector.episodes(m),
                       [AFibDetector.Episode(startTs: 29_833_364 * 60, endTs: 29_833_424 * 60, irregularMinutes: 60)])
    }

    func testBigeminyIsSuppressed() {
        let (t, rr) = build([bigeminy(60)])
        let flags = AFibDetector.beatFlags(times: t, rrSec: rr)
        let m = AFibDetector.minuteStates(times: t, flags: flags, stillMinutes: nil)!
        XCTAssertEqual(flags.filter { $0 }.count, 0)
        XCTAssertEqual(m.states.compactMap { $0 }.count, 60)
        XCTAssertTrue(AFibDetector.episodes(m).isEmpty)
    }

    func testMovingMinutesAreUnreadable() {
        let (t, rr) = build([irregular(60, seed: 7)])
        let flags = AFibDetector.beatFlags(times: t, rrSec: rr)
        let m = AFibDetector.minuteStates(times: t, flags: flags, stillMinutes: [])!
        XCTAssertTrue(m.states.allSatisfy { $0 == nil })
        XCTAssertTrue(AFibDetector.episodes(m).isEmpty)
    }

    func testShortRunIsNotAnEpisodeAndBridgesAreLimited() {
        func states(_ s: [Bool?]) -> AFibDetector.MinuteStates { .init(firstMinute: 0, states: s) }
        XCTAssertTrue(AFibDetector.episodes(states(Array(repeating: true, count: 29))).isEmpty)
        // 20 + 3 regular + 20 bridges into one 40-minute episode; unreadable minutes are neutral.
        let bridged = Array(repeating: true, count: 20) + [false, nil, false, false] + Array(repeating: true, count: 20)
        XCTAssertEqual(AFibDetector.episodes(states(bridged)).map(\.irregularMinutes), [40])
        let broken = Array(repeating: true, count: 20) + Array(repeating: false, count: 4) + Array(repeating: true, count: 20)
        XCTAssertTrue(AFibDetector.episodes(states(broken)).isEmpty)
    }

    func testGapSplitsSegments() {
        // A 60 s hole: the two sides are analysed as separate runs (no cross-gap window).
        let flags = AFibDetector.beatFlags(times: [0, 1, 2, 63, 64], rrSec: [1, 1, 1, 1, 1])
        XCTAssertEqual(flags, [false, false, false, false, false])
    }

    func testBeatTimesSpreadWithinASecond() {
        let rows = [RRInterval(ts: 10, rrMs: 500), RRInterval(ts: 10, rrMs: 500), RRInterval(ts: 11, rrMs: 900)]
        XCTAssertEqual(AFibDetector.beatTimes(rows), [10, 10.25, 11])
    }

    func testStillMinutes() {
        let g = [GravitySample(ts: 60, x: 0, y: 0, z: 1, dynAccel: 0.02),
                 GravitySample(ts: 61, x: 0, y: 0, z: 1, dynAccel: 0.09),
                 GravitySample(ts: 120, x: 0, y: 0, z: 1, dynAccel: 0.02),
                 GravitySample(ts: 150, x: 0, y: 0, z: 1, dynAccel: 0.4),
                 GravitySample(ts: 180, x: 0, y: 0, z: 1, dynAccel: nil)]
        XCTAssertEqual(MotionStillness.stillMinutes(g), [1])
    }

    // MARK: - Breathing disturbances

    /// One hour of 55 s heart-rate cycles (slow 40 s slowing, sharp surge, recovery) over respiratory
    /// variation, then one hour of respiratory variation only.
    private func cvhrSignal() -> (t: [Double], rr: [Double]) {
        var ts: [Double] = [], rs: [Double] = [], acc = 0.0
        while acc < 2 * 3600 {
            let p = acc.truncatingRemainder(dividingBy: 55)
            let bump: Double
            if acc < 3600 {
                if p < 40 { bump = 150 * p / 40 } else if p < 45 { bump = 150 - 350 * (p - 40) / 5 } else { bump = -200 + 200 * (p - 45) / 10 }
            } else { bump = 0 }
            let r = 1000 + 30 * sin(2 * Double.pi * acc / 4) + bump
            acc += r / 1000
            ts.append(Self.t0 + acc); rs.append(r)
        }
        return (ts, rs)
    }

    func testCyclicHeartRateMatchesReference() {
        let (t, rr) = cvhrSignal()
        let r = CvhrDetector.detect(times: t, rrMs: rr)
        XCTAssertEqual(r.dipTimes.count, 65)
        XCTAssertEqual(r.readableHours, 1.994444, accuracy: 1e-6)
        XCTAssertEqual(Array(r.dipTimes.prefix(3)), [1_790_000_089, 1_790_000_144, 1_790_000_200])
        // Every counted dip sits in the cyclic hour.
        XCTAssertTrue(r.dipTimes.allSatisfy { $0 < Self.t0 + 3600 + 60 })
    }

    func testRespiratoryVariationAloneCountsNothing() {
        let (t, rr) = cvhrSignal()
        let flat = zip(t, rr).filter { $0.0 > Self.t0 + 3700 }
        let r = CvhrDetector.detect(times: flat.map(\.0), rrMs: flat.map(\.1))
        XCTAssertEqual(r.dipTimes.count, 0)
        XCTAssertGreaterThan(r.readableHours, 0.9)
    }

    func testMotionMakesSecondsUnreadable() {
        let (t, rr) = cvhrSignal()
        let r = CvhrDetector.detect(times: t, rrMs: rr) { _ in false }
        XCTAssertEqual(r.readableHours, 0)
        XCTAssertNil(r.index)
    }

    func testPercentileMatchesNumpyLinear() {
        XCTAssertEqual(CvhrDetector.percentile([1, 2, 3, 4], 95), 3.85, accuracy: 1e-12)
        XCTAssertEqual(CvhrDetector.percentile([1, 2, 3, 4], 5), 1.15, accuracy: 1e-12)
    }

    // MARK: - Repeating patterns

    func testRhythmPatternNeedsTwoDaysInWindow() {
        let one = HeartBreathingPatterns.rhythm(episodesByDay: ["2026-09-20": 2, "2026-09-01": 1], since: "2026-09-12")
        XCTAssertFalse(one.repeating)
        let two = HeartBreathingPatterns.rhythm(episodesByDay: ["2026-09-20": 1, "2026-09-13": 1, "2026-09-14": 0],
                                                since: "2026-09-12")
        XCTAssertTrue(two.repeating)
        XCTAssertEqual(two.daysWithEpisodes, ["2026-09-13", "2026-09-20"])
    }

    func testBreathingPatternFollowsTenNightHalfRule() {
        func nights(_ elevated: Int, _ normal: Int, hours: Double = 6) -> [String: (index: Double, hours: Double)] {
            var out: [String: (index: Double, hours: Double)] = [:]
            for i in 0..<(elevated + normal) { out[String(format: "2026-09-%02d", i + 1)] = (i < elevated ? 7 : 1, hours) }
            return out
        }
        XCTAssertTrue(HeartBreathingPatterns.breathing(nights: nights(5, 5), since: "2026-08-26").repeating)
        XCTAssertFalse(HeartBreathingPatterns.breathing(nights: nights(4, 6), since: "2026-08-26").repeating)
        XCTAssertFalse(HeartBreathingPatterns.breathing(nights: nights(9, 0), since: "2026-08-26").repeating)
        // Short nights don't count toward the ten.
        XCTAssertFalse(HeartBreathingPatterns.breathing(nights: nights(10, 0, hours: 3), since: "2026-08-26").repeating)
    }
}
