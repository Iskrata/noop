import XCTest
@testable import Strand

/// The hero vessels now draw a snapshot of the sim off the main thread while the live sim keeps stepping.
final class LiquidSimSnapshotTests: XCTestCase {
    func testSnapshotIsDetachedFromTheLiveSim() {
        let sim = LiquidSim(target: 0.6)
        sim.step(now: 100, tilt: 0.2, target: 0.6)
        sim.step(now: 100.016, tilt: 0.2, target: 0.6)
        let frame = sim.snapshot()
        let (level, a, energy, flecks) = (frame.level, frame.a, frame.energy, frame.flecks.count)
        XCTAssertEqual(frame.level, sim.level)
        XCTAssertEqual(frame.a, sim.a)
        sim.splash(12)
        XCTAssertFalse(sim.drops.isEmpty)
        XCTAssertTrue(frame.drops.isEmpty)
        for i in 1...30 { sim.step(now: 100.016 + Double(i) * 0.016, tilt: -0.3, target: 0.2) }
        XCTAssertEqual(frame.level, level)
        XCTAssertEqual(frame.a, a)
        XCTAssertEqual(frame.energy, energy)
        XCTAssertEqual(frame.flecks.count, flecks)
        XCTAssertTrue(frame.drops.isEmpty)
    }
}
