#if os(iOS)
import CallKit
import Foundation

/// Buzzes the strap while a phone call rings (`IncomingCallBuzzPolicy`).
///
/// `CXCallObserver` reports calls to a running process only. NOOP stays alive in the background as a
/// bluetooth-central, woken by the strap's traffic, so a ringing call is usually seen within a wake; after the app
/// is swiped away from the app switcher nothing reports it.
@MainActor
final class IncomingCallBuzz: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    private let buzz: () -> Void
    private var ringing: Set<UUID> = []
    private var loop: Task<Void, Never>?

    init(buzz: @escaping () -> Void) {
        self.buzz = buzz
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let uuid = call.uuid
        let isRinging = IncomingCallBuzzPolicy.isRinging(isOutgoing: call.isOutgoing,
                                                         hasConnected: call.hasConnected, hasEnded: call.hasEnded)
        MainActor.assumeIsolated { update(uuid, isRinging: isRinging) }
    }

    private func update(_ uuid: UUID, isRinging: Bool) {
        if isRinging { ringing.insert(uuid) } else { ringing.remove(uuid) }
        if ringing.isEmpty {
            loop?.cancel()
            loop = nil
        } else if loop == nil, IncomingCallBuzzPolicy.isEnabled() {
            loop = Task { [weak self] in
                let started = Date()
                while !Task.isCancelled,
                      Date().timeIntervalSince(started) < IncomingCallBuzzPolicy.maxBuzzDuration {
                    self?.buzz()
                    try? await Task.sleep(nanoseconds: UInt64(IncomingCallBuzzPolicy.buzzInterval * 1_000_000_000))
                }
                self?.loop = nil
            }
        }
    }
}
#endif
