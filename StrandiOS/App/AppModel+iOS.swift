#if os(iOS)
import Foundation

extension AppModel {
    /// The app's model, for App Intents that run in the background process without opening the app.
    static weak var current: AppModel?

    /// Buzz the strap once it is bonded, waiting up to `timeout` for a link that is still coming up (an intent
    /// can launch the process cold). Returns false when no bonded link arrived.
    func buzzStrapWhenConnected(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !live.bonded {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        buzzStrapOnce()
        return true
    }

    /// Execute any actions queued by App Intents while the app was suspended (mark moment, buzz,
    /// ask coach). Call when the app becomes active. The optional `router` lets the ask-coach
    /// intent navigate to the Coach tab after sending the question.
    func drainPendingIntents(router: NavRouter? = nil) {
        for item in PendingIntents.drain() {
            switch item.action {
            case .markMoment: markMoment(at: item.date ?? Date())
            // #921: the "Buzz Strap" Siri shortcut logged its write but a WHOOP 4.0 never vibrated.
            // The one-shot routine sends the confirmed pattern + RUN_ALARM sequence, acked, so a
            // busy just-foregrounded BLE link can't silently drop it.
            case .buzz:       buzzStrapOnce()
            // K9: "Ask Coach" via Siri — send the queued question to the Coach engine and navigate
            // to the Coach tab so the user sees the response. The question is consumed from a
            // dedicated key (one at a time).
            case .askCoach:
                if let question = PendingIntents.consumeCoachQuestion() {
                    router?.openCoach()
                    Task { @MainActor in
                        await coach.send(question)
                    }
                }
            }
        }
    }
}
#endif
