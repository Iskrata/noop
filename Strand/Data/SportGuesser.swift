import Foundation
import StrandAnalytics
import WhoopProtocol
import WhoopStore

// MARK: - Sport guess for detected activities (fork)
//
// Two tiers, both only ever SUGGESTIONS the wearer confirms in the save sheet:
// 1. Personal: every labelled workout that has strap data (Apple Health, manual, or a detected bout the
//    wearer saved with a sport) is kept as an example — its sport and a small feature vector built from
//    `WorkoutClassFeatures`. A new bout takes the majority sport of its 3 nearest examples, drawn only from
//    sports with at least `minExamples` examples, so suggestions appear only for sports actually done.
// 2. Coarse fallback: `WorkoutTypeClassifier` with "ski" removed. On the 7 labelled strength sessions with
//    strap data (2026-08-26 → 09-18, scratch `wtprobe`) the stock classifier said ski on 5 and strength on
//    1, with strength second on 5 of the ski calls; without ski it names strength on 6 of 7. Walk / run /
//    cycle have no labelled strap-era examples to validate against, so this tier is a weak prior only.

enum SportGuesser {
    struct Example: Codable, Equatable {
        /// Start of the labelled window (unix seconds) — the example's identity.
        let startTs: Int
        /// The workout's stored sport string.
        let sport: String
        let vector: [Double]
    }

    struct Guess: Equatable {
        /// A stored sport string, fit for `WorkoutSource.displaySport` and the save sheet's sport field.
        let sport: String
        /// True when it came from the wearer's own labelled examples.
        let personal: Bool
    }

    static let minExamples = 3

    /// Scale-balanced features: effort (%HRR), HR burstiness, gait composition, motion burstiness, length.
    static func vector(_ f: WorkoutClassFeatures) -> [Double] {
        [
            (f.meanHRRPct ?? 35) / 100,
            min(f.hrCV * 4, 1.5),
            f.stillFraction, f.walkFraction, f.runFraction,
            min(f.motionCV / 2, 1.5),
            log(max(f.durationSec, 60) / 60) / log(180),
        ]
    }

    /// Majority sport of the `k` nearest examples among sports with ≥ `minExamples` examples; nil without a
    /// qualifying sport or without a majority.
    static func personal(_ v: [Double], examples: [Example], k: Int = 3) -> String? {
        let counts = Dictionary(grouping: examples, by: \.sport).mapValues(\.count)
        let eligible = examples.filter { (counts[$0.sport] ?? 0) >= minExamples && $0.vector.count == v.count }
        guard !eligible.isEmpty else { return nil }
        func dist(_ e: Example) -> Double { zip(e.vector, v).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) } }
        let nearest = eligible.sorted { dist($0) < dist($1) }.prefix(k)
        let votes = Dictionary(grouping: nearest, by: \.sport).mapValues(\.count)
        guard let best = votes.max(by: { $0.value < $1.value }), best.value * 2 > nearest.count else { return nil }
        return best.key
    }

    /// The stock coarse classifier without "ski" (see the header), mapped to stored sport names.
    static func coarse(_ f: WorkoutClassFeatures) -> String? {
        let scores = WorkoutTypeClassifier.allScores(f).filter { $0.key != .ski }
        guard let top = scores.max(by: { $0.value < $1.value }), top.value >= 0.5 else { return nil }
        switch top.key {
        case .walk: return "Walking"
        case .run: return "Running"
        case .strength: return "Strength Training"
        case .cycle: return "Cycling"
        case .ski, .other: return nil
        }
    }

    static func guess(_ f: WorkoutClassFeatures, examples: [Example]) -> Guess? {
        if let s = personal(vector(f), examples: examples) { return Guess(sport: s, personal: true) }
        return coarse(f).map { Guess(sport: $0, personal: false) }
    }
}

/// The wearer's labelled examples, in UserDefaults (small: one short vector per labelled workout).
enum SportExampleStore {
    private static let key = "fork.sportExamples.v1"
    private static let cap = 300

    static func all(_ defaults: UserDefaults = .standard) -> [SportGuesser.Example] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SportGuesser.Example].self, from: data)) ?? []
    }

    /// Adds or replaces (same start) examples, keeping the newest `cap`.
    static func upsert(_ new: [SportGuesser.Example], _ defaults: UserDefaults = .standard) {
        guard !new.isEmpty else { return }
        var byStart = Dictionary(all(defaults).map { ($0.startTs, $0) }, uniquingKeysWith: { _, b in b })
        for e in new { byStart[e.startTs] = e }
        let kept = byStart.values.sorted { $0.startTs > $1.startTs }.prefix(cap)
        if let data = try? JSONEncoder().encode(Array(kept)) { defaults.set(data, forKey: key) }
    }
}

extension Repository {
    /// `WorkoutClassFeatures` for a window from the strap's HR, gravity and step (activity-class) streams;
    /// nil without strap HR in the window.
    func sportFeatures(from: Int, to: Int, restingHR: Double?, maxHR: Double?) async -> WorkoutClassFeatures? {
        let hr = await hrSamples(from: from - 60, to: to + 60, limit: 200_000)
        guard !hr.isEmpty else { return nil }
        let gravity = await gravitySamplesUnion(from: from - 60, to: to + 60)
        var steps: [StepSample] = []
        if let store = await storeHandle() {
            for id in [deviceId, Repository.whoopSource] where steps.isEmpty {
                steps = (try? await store.stepSamples(deviceId: id, from: from - 60, to: to + 60, limit: 200_000)) ?? []
            }
        }
        return WorkoutTypeFeatureExtractor.extract(hr: hr, gravity: gravity, steps: steps, start: from, end: to,
                                                   restingHR: restingHR, maxHR: maxHR)
    }

    /// Learns every labelled workout of the last `days` days that has strap data and isn't an example yet.
    func learnSportExamples(days: Int = 120, restingHR: Double?, maxHR: Double?) async {
        let known = Set(SportExampleStore.all().map(\.startTs))
        let cutoff = Int(Date().timeIntervalSince1970) - days * 86_400
        var new: [SportGuesser.Example] = []
        for w in await workoutRows(days: days) where w.startTs >= cutoff && !known.contains(w.startTs)
            && !w.sport.isEmpty && WorkoutSource.classify(w.source) != .detected {
            if let f = await sportFeatures(from: w.startTs, to: w.endTs, restingHR: restingHR, maxHR: maxHR) {
                new.append(.init(startTs: w.startTs, sport: w.sport, vector: SportGuesser.vector(f)))
            }
        }
        SportExampleStore.upsert(new)
    }
}
