import Foundation

/// Pure policy behind the stale-sync alert: notice when the strap hasn't handed the phone/Mac any data
/// for `threshold` (3 hours), so a night lost to iOS killing NOOP overnight — or a swipe-away from the
/// app switcher, which stops the Bluetooth relaunch — doesn't silently disappear.
///
/// A suspended iOS app can't run a timer to detect this itself, so the actual mechanism is a PRE-ARMED
/// local notification (`StaleSyncAlertNotifier`) that the OS delivers on its own schedule: every
/// successful sync cancels the pending request and re-arms a fresh one `threshold` out, so the ONLY way
/// it ever fires is `threshold` really elapsing with no sync landing in between — whether or not NOOP is
/// still alive to notice. This type is just the "when/what" math behind that: no `UserNotifications`
/// import, no `UserDefaults`, no BLE — fully unit-testable in isolation.
enum StaleSyncAlertPolicy {

    /// How long without a sync before the alert should fire.
    static let threshold: TimeInterval = 3 * 3600

    /// Fixed identifier for the pending/delivered notification request. Never varies, so every re-arm
    /// is a cancel-then-replace of the SAME request rather than accumulating duplicates.
    static let identifier = "stale-sync-alert"

    static func title() -> String {
        String(localized: "WHOOP strap not syncing")
    }

    static func body() -> String {
        String(localized: "No data from your strap for 3 hours. Open NOOP to reconnect — and don't swipe NOOP away in the app switcher.")
    }

    /// What (re)arming from a known last-sync anchor should do. The SAME decision drives all three
    /// re-arm sites — a successful sync, app launch/foreground, and the toggle turning on — they differ
    /// only in the `now`/`lastSyncedAt` they pass in, never in the logic.
    enum ArmDecision: Equatable {
        /// Schedule a fresh trigger firing `after` seconds from now. Always > 0.
        case schedule(after: TimeInterval)
        /// Don't schedule anything (the caller is expected to also clear any existing pending/delivered
        /// request). Covers three cases: no paired strap (nothing can go stale), no last-sync time is
        /// known yet, or `threshold` has ALREADY elapsed since the last sync. That last case matters at
        /// launch/foreground/toggle-on: the caller is looking at a strap that's already stale, and firing
        /// an "in 5 seconds" notification while the user has the app open is not wanted — the next real
        /// sync re-arms normally.
        case skip
    }

    /// - Parameters:
    ///   - now: wall-clock "now" at arm time (injectable for tests).
    ///   - lastSyncedAt: the persisted last-sync epoch-seconds, or nil if never synced.
    ///   - hasPairedStrap: whether a strap is currently paired (not deliberately unpaired/archived) —
    ///     there is nothing to go stale otherwise.
    static func arm(now: TimeInterval, lastSyncedAt: TimeInterval?, hasPairedStrap: Bool) -> ArmDecision {
        guard hasPairedStrap, let lastSyncedAt else { return .skip }
        let remaining = threshold - (now - lastSyncedAt)
        guard remaining > 0 else { return .skip }
        return .schedule(after: remaining)
    }
}
