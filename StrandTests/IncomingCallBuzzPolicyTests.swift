import XCTest
@testable import Strand

final class IncomingCallBuzzPolicyTests: XCTestCase {

    func testOnlyAnUnansweredIncomingCallRings() {
        XCTAssertTrue(IncomingCallBuzzPolicy.isRinging(isOutgoing: false, hasConnected: false, hasEnded: false))
        XCTAssertFalse(IncomingCallBuzzPolicy.isRinging(isOutgoing: true, hasConnected: false, hasEnded: false))
        XCTAssertFalse(IncomingCallBuzzPolicy.isRinging(isOutgoing: false, hasConnected: true, hasEnded: false))
        XCTAssertFalse(IncomingCallBuzzPolicy.isRinging(isOutgoing: false, hasConnected: false, hasEnded: true))
    }

    /// Opt-in: an unset key must read off, unlike the in-session `HapticPrefs` cues.
    func testTheBuzzIsOffUntilTurnedOn() {
        let defaults = UserDefaults(suiteName: "IncomingCallBuzzPolicyTests")!
        defaults.removePersistentDomain(forName: "IncomingCallBuzzPolicyTests")
        XCTAssertFalse(IncomingCallBuzzPolicy.isEnabled(defaults))
        defaults.set(true, forKey: IncomingCallBuzzPolicy.enabledKey)
        XCTAssertTrue(IncomingCallBuzzPolicy.isEnabled(defaults))
    }
}
