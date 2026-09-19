#if os(iOS)
import Foundation
import AppIntents
import ActivityKit

/// Fork: the Stop button on the Live HR Live Activity. Ends the activity and keeps it off until the strap
/// next disconnects (a new session), via a flag in the shared App Group (`LiveHRActivitySnooze`). Heart-rate
/// recording itself is untouched: it feeds sleep, HRV and recovery, so only the banner stops.
///
/// A `LiveActivityIntent` runs in the app's process (launched in the background if needed); this file is in
/// both the app and the widget extension, which renders the button.
public struct StopLiveHRIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop Live HR"
    public static var description = IntentDescription("End the Live HR Live Activity until the strap reconnects.")
    public static var openAppWhenRun = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        LiveHRActivitySnooze.set(true)
        for activity in Activity<NOOPActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

/// The "user stopped Live HR" flag, shared by the intent and the app's `LiveActivityController`.
public enum LiveHRActivitySnooze {
    private static let key = "fork.liveHRActivitySnoozed"
    private static var defaults: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.suiteName) ?? .standard }

    public static var isOn: Bool { defaults.bool(forKey: key) }
    public static func set(_ on: Bool) { defaults.set(on, forKey: key) }
}
#endif
