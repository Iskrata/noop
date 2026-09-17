import Foundation
import UserNotifications

/// Notifies the user when the strap hasn't synced with the phone/Mac for
/// `StaleSyncAlertPolicy.threshold` (3 hours) — motivated by iOS killing NOOP overnight, or a swipe-away
/// from the app switcher (which stops the Bluetooth relaunch), each silently losing a night of recovery
/// data. A notice catches both.
///
/// A suspended app can't run its own timer to notice a stale strap, so this is a PRE-ARMED local
/// notification: `UNTimeIntervalNotificationTrigger(timeInterval: 3h, repeats: false)` under a fixed
/// identifier, cancelled and re-added on every successful sync. As long as syncs keep landing the
/// request keeps getting replaced before it can ever fire; the only way it fires is `threshold` really
/// elapsing with nothing landing in between — which the OS enforces on its own schedule, so it still
/// fires with NOOP dead or suspended.
///
/// Mirrors `BatteryNotifier` / `WindDownNudge`: pure policy decides WHEN and WHAT
/// (`StaleSyncAlertPolicy`), this type only touches `UNUserNotificationCenter`. Authorization is
/// requested through the shared `BatteryNotifier.requestAuthorization()` helper when the toggle turns
/// on — no second `requestAuthorization` call site.
enum StaleSyncAlertNotifier {

    /// (Re)arm from a known last-sync anchor — the single entry point for all three re-arm sites: a
    /// successful sync (`lastSyncedAt` just advanced), app launch/foreground (re-derive the remaining
    /// time from `now`), and the toggle turning on/off. Always clears any existing pending + delivered
    /// copy first — so disabling the toggle, an unpaired strap, and a fresh sync retiring a stale
    /// delivered banner all go through the same call site — then re-schedules only when `enabled` and
    /// the policy says there's something to schedule.
    static func arm(now: TimeInterval = Date().timeIntervalSince1970,
                    lastSyncedAt: TimeInterval?,
                    hasPairedStrap: Bool,
                    enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [StaleSyncAlertPolicy.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [StaleSyncAlertPolicy.identifier])
        guard enabled,
              case .schedule(let after) = StaleSyncAlertPolicy.arm(
                now: now, lastSyncedAt: lastSyncedAt, hasPairedStrap: hasPairedStrap)
        else { return }
        // Authorization is requested once via BatteryNotifier.requestAuthorization() when the toggle
        // turns on; here we only check status (no second system prompt) — mirrors BatteryNotifier.post().
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = StaleSyncAlertPolicy.title()
            content.body = StaleSyncAlertPolicy.body()
            content.sound = .default
            // Matches BatteryNotifier's escalation alerts — .timeSensitive so a truly silent night can
            // break through a sleep Focus. Harmless without the entitlement: the OS silently treats it
            // as .active.
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
            center.add(UNNotificationRequest(identifier: StaleSyncAlertPolicy.identifier,
                                             content: content, trigger: trigger))
        }
    }
}
