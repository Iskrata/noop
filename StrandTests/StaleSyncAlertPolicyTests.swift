import XCTest
@testable import Strand

/// `StaleSyncAlertPolicy` — the pure "when/what" math behind the stale-sync alert. Notifies the user
/// when the strap hasn't synced for 3 hours, delivered by a PRE-ARMED `UNTimeIntervalNotificationTrigger`
/// so it fires even if iOS has killed/suspended NOOP. These tests exercise `arm(now:lastSyncedAt:
/// hasPairedStrap:)`, the single decision function shared by all three re-arm sites (a successful sync,
/// app launch/foreground, and the toggle turning on).
final class StaleSyncAlertPolicyTests: XCTestCase {

    // 1. A fresh sync (lastSyncedAt == now) schedules the full 3h out.
    func testFreshSyncSchedulesFullThreshold() {
        let now: TimeInterval = 1_000_000
        let decision = StaleSyncAlertPolicy.arm(now: now, lastSyncedAt: now, hasPairedStrap: true)
        XCTAssertEqual(decision, .schedule(after: StaleSyncAlertPolicy.threshold))
    }

    // 2. Re-arming partway through the window (e.g. at foreground, 1h after the last sync) schedules
    //    only the REMAINING time, not the full threshold again.
    func testForegroundReArmSchedulesRemainingTime() {
        let now: TimeInterval = 1_000_000
        let lastSyncedAt = now - 3600   // synced 1h ago
        let decision = StaleSyncAlertPolicy.arm(now: now, lastSyncedAt: lastSyncedAt, hasPairedStrap: true)
        XCTAssertEqual(decision, .schedule(after: StaleSyncAlertPolicy.threshold - 3600))
    }

    // 3. Already stale at launch/foreground (more than 3h since the last sync): do NOT schedule an
    //    imminent fire — the user is looking at the app right now. The next real sync re-arms normally.
    func testAlreadyStaleAtLaunchDoesNotSchedule() {
        let now: TimeInterval = 1_000_000
        let lastSyncedAt = now - StaleSyncAlertPolicy.threshold - 60   // 1 minute past the line
        let decision = StaleSyncAlertPolicy.arm(now: now, lastSyncedAt: lastSyncedAt, hasPairedStrap: true)
        XCTAssertEqual(decision, .skip)
    }

    // 3b. Exactly at the threshold (remaining == 0) is also a skip — `remaining > 0` is the boundary,
    //     not `>= 0`, so a zero-length trigger is never scheduled.
    func testExactlyAtThresholdSkips() {
        let now: TimeInterval = 1_000_000
        let lastSyncedAt = now - StaleSyncAlertPolicy.threshold
        let decision = StaleSyncAlertPolicy.arm(now: now, lastSyncedAt: lastSyncedAt, hasPairedStrap: true)
        XCTAssertEqual(decision, .skip)
    }

    // 4. No paired strap (deliberately unpaired) never schedules, no matter how recent the last sync.
    func testNoPairedStrapNeverSchedules() {
        let now: TimeInterval = 1_000_000
        let decision = StaleSyncAlertPolicy.arm(now: now, lastSyncedAt: now, hasPairedStrap: false)
        XCTAssertEqual(decision, .skip)
    }

    // 5. No known last-sync time yet (never synced) skips rather than firing off some fabricated anchor.
    func testNoLastSyncedAtSkips() {
        let decision = StaleSyncAlertPolicy.arm(now: 1_000_000, lastSyncedAt: nil, hasPairedStrap: true)
        XCTAssertEqual(decision, .skip)
    }

    // 6. Threshold is exactly 3 hours, and the identifier is fixed (re-arming replaces the same request
    //    rather than accumulating duplicates).
    func testThresholdAndIdentifier() {
        XCTAssertEqual(StaleSyncAlertPolicy.threshold, 3 * 3600)
        XCTAssertEqual(StaleSyncAlertPolicy.identifier, "stale-sync-alert")
    }

    // 7. Title/body are non-empty and the body names the threshold in a way a user can act on.
    func testTitleAndBodyAreNonEmptyAndMentionTheWindow() {
        XCTAssertFalse(StaleSyncAlertPolicy.title().isEmpty)
        let body = StaleSyncAlertPolicy.body()
        XCTAssertFalse(body.isEmpty)
        XCTAssertTrue(body.contains("3 hours"))
    }
}
