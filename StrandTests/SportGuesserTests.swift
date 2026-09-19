import XCTest
import StrandAnalytics
@testable import Strand

/// Fork: sport suggestions for detected bouts (`SportGuesser`).
final class SportGuesserTests: XCTestCase {
    private func ex(_ sport: String, _ v: [Double], _ t: Int) -> SportGuesser.Example {
        .init(startTs: t, sport: sport, vector: v)
    }

    func testPersonalNeedsThreeExamplesOfASport() {
        let two = [ex("Tennis", [0.5, 1], 1), ex("Tennis", [0.5, 1], 2)]
        XCTAssertNil(SportGuesser.personal([0.5, 1], examples: two))
        let three = two + [ex("Tennis", [0.52, 1], 3)]
        XCTAssertEqual(SportGuesser.personal([0.5, 1], examples: three), "Tennis")
    }

    func testPersonalPicksTheNearestSportByMajority() {
        let examples = (0..<3).map { ex("Tennis", [0.6, 1.2], $0) } + (3..<6).map { ex("Strength Training", [0.3, 0.4], $0) }
        XCTAssertEqual(SportGuesser.personal([0.58, 1.1], examples: examples), "Tennis")
        XCTAssertEqual(SportGuesser.personal([0.32, 0.45], examples: examples), "Strength Training")
    }

    func testExampleStoreUpsertsByStart() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "SportGuesserTests"))
        d.removePersistentDomain(forName: "SportGuesserTests")
        SportExampleStore.upsert([ex("Walking", [1], 10)], d)
        SportExampleStore.upsert([ex("Tennis", [1], 10), ex("Running", [2], 20)], d)
        XCTAssertEqual(SportExampleStore.all(d).map(\.sport).sorted(), ["Running", "Tennis"])
    }
}
