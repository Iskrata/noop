import XCTest
@testable import StrandDesign

/// Pins the hide-scores pref contract (#hide-scores): the storage key, and the TRUE default that must
/// hold even before any Settings screen has ever run (a fresh install, or a non-View reader like the
/// widget-snapshot publisher or a notifier reading `UserDefaults.standard` directly).
final class ScoreVisibilityTests: XCTestCase {
    private let suiteName = "ScoreVisibilityTests"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ScoreVisibility.hiddenKey)
        super.tearDown()
    }

    func testStorageKey() {
        XCTAssertEqual(ScoreVisibility.hiddenKey, "noop.hideScores")
    }

    func testDefaultsToTrueWhenNeverWritten() {
        UserDefaults.standard.removeObject(forKey: ScoreVisibility.hiddenKey)
        XCTAssertTrue(ScoreVisibility.hidden)
    }

    func testReflectsAnExplicitFalse() {
        UserDefaults.standard.set(false, forKey: ScoreVisibility.hiddenKey)
        XCTAssertFalse(ScoreVisibility.hidden)
        UserDefaults.standard.removeObject(forKey: ScoreVisibility.hiddenKey)
    }

    func testReflectsAnExplicitTrue() {
        UserDefaults.standard.set(true, forKey: ScoreVisibility.hiddenKey)
        XCTAssertTrue(ScoreVisibility.hidden)
        UserDefaults.standard.removeObject(forKey: ScoreVisibility.hiddenKey)
    }
}
