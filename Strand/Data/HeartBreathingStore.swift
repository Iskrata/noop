import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// Fork: runs the irregular-rhythm (`AFibDetector`) and breathing-disturbance (`CvhrDetector`) screens
/// after each re-score pass, stores the per-day results in `metricSeries` under the computed device id, and
/// publishes them to Lab → Heart & Breathing and the Today banner. Method and validation:
/// docs/fork/HEART_BREATHING.md. Nothing here is written to Apple Health, notified, or buzzed.
@MainActor
final class HeartBreathingStore: ObservableObject {
    static let shared = HeartBreathingStore()

    struct RhythmDay: Equatable {
        let readableMinutes: Int
        let irregularMinutes: Int
        let episodes: Int
        let episodeMinutes: Int
        let firstEpisodeStart: Int?
    }

    struct BreathingNight: Equatable {
        let index: Double
        let readableHours: Double
        let dips: Int
    }

    enum Key {
        static let readable = "rhythm_readable_min"
        static let irregular = "rhythm_irregular_min"
        static let episodes = "rhythm_episodes"
        static let episodeMinutes = "rhythm_episode_min"
        static let firstEpisode = "rhythm_first_episode_ts"
        static let index = "breathing_index"
        static let hours = "breathing_hours"
        static let dips = "breathing_dips"
    }

    /// Bump when either detector changes: the next pass then recomputes the whole history window.
    static let algorithmVersion = 1
    private static let versionKey = "fork.heartBreathing.algorithmVersion"
    /// Days kept, read and backfilled — the breathing rule's 30-night window.
    static let historyDays = HeartBreathingPatterns.breathingWindowDays
    /// Days re-run on a normal pass: today and yesterday (late-synced beats land there).
    static let routineDays = 2
    /// Context read either side of a calendar day, so an episode across midnight is seen whole.
    nonisolated static let dayPadSec = 3 * 3600
    /// Sleep sessions shorter than this are naps and don't make a breathing night.
    nonisolated static let minSessionSec = 3 * 3600

    @Published private(set) var rhythm: [String: RhythmDay] = [:]
    @Published private(set) var breathing: [String: BreathingNight] = [:]
    @Published private(set) var loaded = false
    private var running = false

    nonisolated static func dayKey(_ ts: Int) -> String {
        AnalyticsEngine.dayString(ts, offsetSec: TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts))))
    }

    static func dayKey(daysAgo: Int, from now: Date = Date()) -> String {
        let cal = Calendar.current
        let d = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now)) ?? now
        return dayKey(Int(d.timeIntervalSince1970))
    }

    var rhythmPattern: HeartBreathingPatterns.RhythmPattern {
        HeartBreathingPatterns.rhythm(episodesByDay: rhythm.mapValues(\.episodes),
                                      since: Self.dayKey(daysAgo: HeartBreathingPatterns.rhythmWindowDays - 1))
    }

    var breathingPattern: HeartBreathingPatterns.BreathingPattern {
        HeartBreathingPatterns.breathing(nights: breathing.mapValues { ($0.index, $0.readableHours) },
                                         since: Self.dayKey(daysAgo: HeartBreathingPatterns.breathingWindowDays - 1))
    }

    // MARK: - Load

    func loadIfNeeded(repo: Repository) async {
        guard !loaded, let store = await repo.storeHandle() else { return }
        await load(store: store, computedId: Self.computedId(repo))
    }

    /// The engine's STABLE canonical computed id (IntelligenceEngine writes every computed row there), not
    /// the active strap's.
    private static func computedId(_ repo: Repository) -> String { Repository.whoopSource + "-noop" }

    private func load(store: WhoopStore, computedId: String) async {
        let from = Self.dayKey(daysAgo: Self.historyDays - 1), to = Self.dayKey(daysAgo: 0)
        func series(_ key: String) async -> [String: Double] {
            let pts = (try? await store.metricSeries(deviceId: computedId, key: key, from: from, to: to)) ?? []
            return Dictionary(pts.map { ($0.day, $0.value) }, uniquingKeysWith: { $1 })
        }
        let readable = await series(Key.readable), irregular = await series(Key.irregular)
        let episodes = await series(Key.episodes), episodeMinutes = await series(Key.episodeMinutes)
        let first = await series(Key.firstEpisode)
        let index = await series(Key.index), hours = await series(Key.hours), dips = await series(Key.dips)
        rhythm = Dictionary(uniqueKeysWithValues: readable.map { day, r in
            (day, RhythmDay(readableMinutes: Int(r), irregularMinutes: Int(irregular[day] ?? 0),
                            episodes: Int(episodes[day] ?? 0), episodeMinutes: Int(episodeMinutes[day] ?? 0),
                            firstEpisodeStart: first[day].map(Int.init)))
        })
        breathing = Dictionary(uniqueKeysWithValues: index.map { day, i in
            (day, BreathingNight(index: i, readableHours: hours[day] ?? 0, dips: Int(dips[day] ?? 0)))
        })
        loaded = true
    }

    // MARK: - Pass

    /// Run after a re-score pass. Recomputes today and yesterday — or the whole history window the first
    /// time and after an algorithm change — then reloads what the screens show.
    func refresh(repo: Repository, log: @escaping (String) -> Void) async {
        guard !running, let store = await repo.storeHandle() else { return }
        running = true
        defer { running = false }
        let computedId = Self.computedId(repo)
        let owner = (try? DeviceRegistryStore(dbQueue: store.registryWriter).activeDeviceId()) ?? repo.deviceId
        let backfill = UserDefaults.standard.integer(forKey: Self.versionKey) != Self.algorithmVersion
        let days = backfill ? Self.historyDays : Self.routineDays
        let (points, lines) = await Task.detached(priority: .utility) {
            await Self.compute(store: store, owner: owner, ownerIsCanonical: owner == Repository.whoopSource,
                               computedId: computedId, days: days)
        }.value
        lines.forEach(log)
        if !points.isEmpty { _ = try? await store.upsertMetricSeries(points, deviceId: computedId) }
        if backfill {
            UserDefaults.standard.set(Self.algorithmVersion, forKey: Self.versionKey)
            log("heart-breathing backfill days=\(days) points=\(points.count)")
        }
        await load(store: store, computedId: computedId)
    }

    /// The day loop, off the main actor. Returns the rows to store and the evidence lines to log.
    nonisolated private static func compute(store: WhoopStore, owner: String, ownerIsCanonical: Bool,
                                            computedId: String, days: Int) async -> ([MetricPoint], [String]) {
        let cal = Calendar.current
        let now = Date()
        let nowTs = Int(now.timeIntervalSince1970)
        let activeWhoop5 = (try? await store.isWhoop5RRSource(deviceId: owner)) ?? true
        // Same R-R read policy as the scoring engine (IntelligenceEngine's rrWindow).
        let alias = activeWhoop5 && ownerIsCanonical
        var points: [MetricPoint] = [], lines: [String] = []
        for daysAgo in stride(from: days - 1, through: 0, by: -1) {
            guard let startDate = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now)),
                  let endDate = cal.date(byAdding: .day, value: 1, to: startDate) else { continue }
            let dayStart = Int(startDate.timeIntervalSince1970), dayEnd = Int(endDate.timeIntervalSince1970)
            let day = dayKey(dayStart)
            let lo = dayStart - dayPadSec, hi = min(dayEnd + dayPadSec, nowTs)

            let rr = (try? await store.rrIntervals(deviceId: owner, from: lo, to: hi, limit: StreamReadCap.rr,
                                                   unlabelledAliasOfWhoop5: alias)) ?? []
            let gravity = (try? await store.gravitySamples(deviceId: owner, from: lo, to: hi,
                                                           limit: StreamReadCap.gravity)) ?? []
            let still = MotionStillness.stillMinutes(gravity)
            if let s = AFibDetector.analyze(rr, stillMinutes: still, dayOf: dayKey)[day] {
                points += [MetricPoint(day: day, key: Key.readable, value: Double(s.readableMinutes)),
                           MetricPoint(day: day, key: Key.irregular, value: Double(s.irregularMinutes)),
                           MetricPoint(day: day, key: Key.episodes, value: Double(s.episodes.count)),
                           MetricPoint(day: day, key: Key.episodeMinutes,
                                       value: Double(s.episodes.map(\.irregularMinutes).reduce(0, +)))]
                if let first = s.episodes.first {
                    points.append(MetricPoint(day: day, key: Key.firstEpisode, value: Double(first.startTs)))
                    // Rare-event evidence, always on: what the screen saw, not what it means.
                    lines.append("heart-breathing rhythm day=\(day) episodes=\(s.episodes.count) "
                        + "irregularMin=\(s.irregularMinutes) readableMin=\(s.readableMinutes)")
                }
            }

            // The breathing night belongs to the day its (non-nap) sleep ends on.
            let sessions = ((try? await store.sleepSessions(deviceId: computedId, from: dayStart - 86_400,
                                                            to: dayEnd, limit: 20)) ?? [])
                .filter { $0.endTs >= dayStart && $0.endTs < dayEnd && $0.endTs - $0.startTs >= minSessionSec }
            var dips = 0, hours = 0.0
            for s in sessions {
                let beats = (try? await store.rrIntervals(deviceId: owner, from: s.startTs, to: s.endTs,
                                                          limit: StreamReadCap.rr, unlabelledAliasOfWhoop5: alias)) ?? []
                let sessionStill = s.startTs >= lo ? still : MotionStillness.stillMinutes(
                    (try? await store.gravitySamples(deviceId: owner, from: s.startTs, to: s.endTs,
                                                     limit: StreamReadCap.gravity)) ?? [])
                let r = CvhrDetector.analyze(beats, stillMinutes: sessionStill)
                dips += r.dipTimes.count; hours += r.readableHours
            }
            if hours > 0 {
                let index = Double(dips) / hours
                points += [MetricPoint(day: day, key: Key.index, value: index),
                           MetricPoint(day: day, key: Key.hours, value: hours),
                           MetricPoint(day: day, key: Key.dips, value: Double(dips))]
                if index >= CvhrDetector.elevatedIndex {
                    lines.append("heart-breathing breathing day=\(day) index=\(String(format: "%.1f", index)) "
                        + "dips=\(dips) readableH=\(String(format: "%.1f", hours))")
                }
            }
        }
        return (points, lines)
    }
}
