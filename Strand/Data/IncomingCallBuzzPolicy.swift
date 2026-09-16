import Foundation

/// When the strap buzzes for an incoming phone call. iOS-only in practice (CallKit), kept framework-free so the
/// rules are unit-testable in the macOS test target.
enum IncomingCallBuzzPolicy {
    /// Opt-in. Unlike `HapticPrefs`, an unset key reads OFF: this buzz is not feedback to something you started.
    static let enabledKey = "noop.incomingCallBuzz.enabled"
    /// Seconds between buzzes while a call rings.
    static let buzzInterval: TimeInterval = 3
    /// A call that is never answered or ended (a missed state CallKit fails to report) stops buzzing after this.
    static let maxBuzzDuration: TimeInterval = 60

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// A call is ringing at you: incoming, not yet answered, not ended.
    static func isRinging(isOutgoing: Bool, hasConnected: Bool, hasEnded: Bool) -> Bool {
        !isOutgoing && !hasConnected && !hasEnded
    }
}
