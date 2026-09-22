import Foundation
import StrandImport
import WhoopStore

/// Fork: whether last night may still be growing, so Today, Sleep and the Coach wait for it instead of
/// showing a score for a night the strap hasn't seen end.
///
/// A pass scores whatever has synced. Before the morning's backlog lands, or while the wearer is still in
/// bed, the latest night ends at the newest synced heart rate and every later pass lengthens it. On
/// 2026-09-22 a night slept 00:07 → 08:54 was scored at 331, 376, 416, 417, 487 and 501 min, each a new
/// Sleep score and Charge, and the day's coaching line was written from a "4.9h" night. The engine
/// publishes the latest night's end and the newest heart rate its pass read; the night counts as open
/// while `HealthWriteback.nightIsStillOpen` says so (the rule that already holds it out of Apple Health),
/// so the scores appear once, after the strap has seen the wearer up for `openNightMarginSeconds`.
enum OpenNight {
    private static let key = "fork.openNight"

    /// The latest detected night as one pass saw it.
    struct Probe: Equatable {
        /// The day the night is scored under (`DailyMetric.day`).
        let wakeDay: String
        let endTs: Int
        /// The newest heart rate the pass read for that day: data that lands after the read can't close a
        /// night the pass never saw continue.
        let newestHeartRateTs: Int

        func isOpen(now: Int) -> Bool {
            HealthWriteback.nightIsStillOpen(endTs: endTs, newestHeartRateTs: newestHeartRateTs, now: now)
        }
    }

    // MARK: Pure

    /// The night that ends last across a pass's scored days, with the heart-rate frontier of its day.
    static func probe(nights: [(day: String, sleeps: [CachedSleepSession])],
                      newestHeartRateByDay: [String: Int]) -> Probe? {
        let latest = nights.flatMap { n in n.sleeps.map { (day: n.day, endTs: $0.endTs) } }
            .max { $0.endTs < $1.endTs }
        guard let latest, let newest = newestHeartRateByDay[latest.day] else { return nil }
        return Probe(wakeDay: latest.day, endTs: latest.endTs, newestHeartRateTs: newest)
    }

    // MARK: Published

    static func publish(_ probe: Probe?, defaults: UserDefaults = .standard) {
        guard let probe else { defaults.removeObject(forKey: key); return }
        defaults.set(["day": probe.wakeDay, "end": probe.endTs, "hr": probe.newestHeartRateTs] as [String: Any],
                     forKey: key)
    }

    static func published(defaults: UserDefaults = .standard) -> Probe? {
        guard let d = defaults.dictionary(forKey: key), let day = d["day"] as? String,
              let end = d["end"] as? Int, let hr = d["hr"] as? Int else { return nil }
        return Probe(wakeDay: day, endTs: end, newestHeartRateTs: hr)
    }

    /// True while `day`'s night is still open: its scores, coaching line and sleep tips wait.
    static func isOpen(day: String, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard let probe = published(defaults: defaults), probe.wakeDay == day else { return false }
        return probe.isOpen(now: Int(now.timeIntervalSince1970))
    }
}
