import XCTest
import StrandAnalytics
import WhoopProtocol
import WhoopStore
@testable import Strand

/// Fork: the Today Activities list (`DayActivities`).
final class DayActivitiesTests: XCTestCase {
    private let scoring = DayActivities.Scoring(maxHR: 190, restingHR: 55, method: .whoopCalibrated, sex: "male")

    private func workout(_ start: Int, _ end: Int, strain: Double? = nil) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: "Running", source: "apple-health",
                   durationS: Double(end - start), energyKcal: nil, avgHr: nil, maxHr: nil, strain: strain,
                   distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
    }

    private func night(_ start: Int, _ end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    /// 1 Hz samples at a constant bpm.
    private func hr(_ from: Int, _ to: Int, bpm: Int) -> [HRSample] {
        (from...to).map { HRSample(ts: $0, bpm: bpm) }
    }

    func testHrSliceIsInclusiveAndBounded() {
        let stream = hr(0, 100, bpm: 60)
        XCTAssertEqual(DayActivities.hrSlice(stream, from: 10, to: 20).map(\.ts), Array(10...20))
        XCTAssertTrue(DayActivities.hrSlice(stream, from: 200, to: 300).isEmpty)
        XCTAssertTrue(DayActivities.hrSlice(stream, from: 20, to: 10).isEmpty)
    }

    func testSleepsEndingInsideTheWindowBelongToTheDay() {
        let blocks = [night(-30_000, -100), night(-20_000, 25_000), night(40_000, 43_000), night(80_000, 90_000)]
        XCTAssertEqual(DayActivities.sleepsEnding(in: blocks, from: 0, to: 86_399).map(\.endTs), [25_000, 43_000])
    }

    func testBuildScoresEachActivityFromItsOwnSliceNewestFirst() throws {
        // Resting day at 60 bpm, a hard 20-min workout at 160 and a detected 15-min bout at 150.
        var stream = hr(0, 9_999, bpm: 60)
        stream += hr(10_000, 11_200, bpm: 160)
        stream += hr(11_201, 19_999, bpm: 60)
        stream += hr(20_000, 20_900, bpm: 150)
        let dayEffort = try XCTUnwrap(StrainScorer.strain(stream, maxHR: 190, restingHR: 55,
                                                          method: .whoopCalibrated, sex: "male"))
        let bout = DetectedWorkout(startSec: 20_000, endSec: 20_900, avgBpm: 150, peakBpm: 150, durationMin: 15)
        let rows = DayActivities.build(sleeps: [night(-20_000, 5_000)], workouts: [workout(10_000, 11_200)],
                                       detected: [bout], mindful: [30_000...30_600], hr: stream, scoring: scoring)

        XCTAssertEqual(rows.map(\.startTs), [30_000, 20_000, 10_000, -20_000])
        let mindful = rows[0], auto = rows[1], run = rows[2]
        XCTAssertEqual(mindful.kind, .mindful)
        XCTAssertNil(mindful.effort)
        XCTAssertGreaterThan(try XCTUnwrap(run.effort), try XCTUnwrap(auto.effort))
        XCTAssertLessThanOrEqual(try XCTUnwrap(run.effort), dayEffort)
        XCTAssertNil(rows[3].effort)
    }

    func testWorkoutWithoutStrapHeartRateKeepsItsStoredStrain() {
        let rows = DayActivities.build(sleeps: [], workouts: [workout(1_000, 2_000, strain: 42)], detected: [],
                                       hr: [], scoring: scoring)
        XCTAssertEqual(rows.first?.effort, 42)
    }

    func testDetectedBoutsBelowHalfAStrainAreDropped() {
        // A 15-min bout barely above resting earns almost no Effort; an unscorable bout (no HR) has none.
        let light = DetectedWorkout(startSec: 1_000, endSec: 1_900, avgBpm: 62, peakBpm: 62, durationMin: 15)
        let blind = DetectedWorkout(startSec: 5_000, endSec: 5_900, avgBpm: 120, peakBpm: 120, durationMin: 15)
        let rows = DayActivities.build(sleeps: [], workouts: [], detected: [light, blind],
                                       hr: hr(1_000, 1_900, bpm: 62), scoring: scoring)
        XCTAssertTrue(rows.isEmpty)
    }

    func testDetectedBoutIsNamedByTheStrapsGait() throws {
        let bout = DetectedWorkout(startSec: 0, endSec: 900, avgBpm: 150, peakBpm: 150, durationMin: 15)
        let walking = (0...900).map { StepSample(ts: $0, counter: $0, activityClass: 1) }
        let rows = DayActivities.build(sleeps: [], workouts: [], detected: [bout], hr: hr(0, 900, bpm: 150),
                                       steps: walking, scoring: scoring)
        let row = try XCTUnwrap(rows.first)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(row.effort), DayActivities.minDetectedEffort)
        XCTAssertEqual(row.kind, .detected(bout, gait: .walk))
        let noSteps = DayActivities.build(sleeps: [], workouts: [], detected: [bout], hr: hr(0, 900, bpm: 150),
                                          scoring: scoring)
        XCTAssertEqual(noSteps.first?.kind, .detected(bout, gait: nil))
    }
}
