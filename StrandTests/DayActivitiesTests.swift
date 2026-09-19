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

    func testLoadShareMapsEffortBackToLoadBeforeDividing() throws {
        let d = StrainScorer.logMapDenominator(method: .whoopCalibrated, sex: "male")
        func effort(_ load: Double) -> Double { StrainScorer.maxStrain * log(load + 1) / log(d) }
        let share = try XCTUnwrap(DayActivities.loadShare(activityEffort: effort(90), dayEffort: effort(120),
                                                          method: .whoopCalibrated, sex: "male"))
        XCTAssertEqual(share, 0.75, accuracy: 1e-9)
        // Dividing the Efforts themselves would have claimed ~0.94 for the same activity.
        XCTAssertGreaterThan(effort(90) / effort(120), 0.9)
    }

    func testLoadShareIsCappedAndNilWithoutADay() {
        XCTAssertEqual(DayActivities.loadShare(activityEffort: 60, dayEffort: 40, method: .whoopCalibrated, sex: "male"), 1)
        XCTAssertNil(DayActivities.loadShare(activityEffort: 10, dayEffort: 0, method: .whoopCalibrated, sex: "male"))
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
                                       detected: [bout], hr: stream, dayEffort: dayEffort, scoring: scoring)

        XCTAssertEqual(rows.map(\.startTs), [20_000, 10_000, -20_000])
        let run = rows[1], auto = rows[0]
        XCTAssertGreaterThan(try XCTUnwrap(run.effort), try XCTUnwrap(auto.effort))
        XCTAssertLessThanOrEqual(try XCTUnwrap(run.effort), dayEffort)
        // The resting minutes earn nothing, so the two activities hold the whole day's load between them.
        XCTAssertEqual(try XCTUnwrap(run.share) + (try XCTUnwrap(auto.share)), 1, accuracy: 0.02)
        XCTAssertNil(rows[2].effort)
    }

    func testWorkoutWithoutStrapHeartRateKeepsItsStoredStrain() {
        let rows = DayActivities.build(sleeps: [], workouts: [workout(1_000, 2_000, strain: 42)], detected: [],
                                       hr: [], dayEffort: nil, scoring: scoring)
        XCTAssertEqual(rows.first?.effort, 42)
        XCTAssertNil(rows.first?.share)
    }
}
