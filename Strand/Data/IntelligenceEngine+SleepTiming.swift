import Foundation
import StrandAnalytics
import WhoopStore

extension IntelligenceEngine {
    /// Fork: WHOOP-style consistency per wake day (`PersonalSleepScore.consistency`) from the main (longest)
    /// stored block of each night, INCLUDING last night — unlike `computeHabitualSleep`, which stops at
    /// local midnight so the growing night can't move the learned traits. `fresh` are the nights the
    /// running pass just detected and has not written yet; they win over their stored copies.
    static func sleepConsistencyByWakeDay(store: WhoopStore, importedId: String, computedId: String,
                                          from: Int, to: Int, offsetSec: Int,
                                          fresh: [CachedSleepSession] = []) async -> [String: Double] {
        let imported = (try? await store.sleepSessions(deviceId: importedId, from: from, to: to, limit: 4000)) ?? []
        let computed = (try? await store.sleepSessions(deviceId: computedId, from: from, to: to, limit: 4000)) ?? []
        var mainByDay: [String: (start: Int, end: Int)] = [:]
        let freshStarts = Set(fresh.map(\.startTs))
        let all = imported + computed.filter { !freshStarts.contains($0.startTs) } + fresh
        for s in SleepSessionDedup.dedupe(all, freshStarts: freshStarts).kept
        where s.endTs > s.effectiveStartTs {
            let day = AnalyticsEngine.dayString(s.endTs, offsetSec: offsetSec)
            if let cur = mainByDay[day], cur.end - cur.start >= s.endTs - s.effectiveStartTs { continue }
            mainByDay[day] = (s.effectiveStartTs, s.endTs)
        }
        // Minutes on one continuous clock: bedtimes after noon stay put, early-morning ones wrap past 24 h;
        // wakes are plain minutes after midnight.
        func clock(_ ts: Int, evening: Bool) -> Double {
            let secs = ((ts + offsetSec) % 86_400 + 86_400) % 86_400
            let m = Double(secs) / 60
            return evening && m < 12 * 60 ? m + 1440 : m
        }
        let days = mainByDay.keys.sorted()
        var out: [String: Double] = [:]
        for (i, day) in days.enumerated() {
            let window = days[max(0, i - 3)...i].compactMap { mainByDay[$0] }
            if let c = PersonalSleepScore.consistency(onsets: window.map { clock($0.start, evening: true) },
                                                      wakes: window.map { clock($0.end, evening: false) }) {
                out[day] = c
            }
        }
        return out
    }
}
