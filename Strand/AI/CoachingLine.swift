import Foundation
import WhoopStore

/// Fork: the one-sentence COACHING line under Today's rings (Bevel's). Generated ONCE per logical day, the
/// first time both of today's scores (Charge and Rest) are in, then served from the Coach reply cache
/// (`CoachReplies.swift`) for the rest of the day. nil means "use the on-device line".
extension AICoachEngine {

    private static let coachingMaxWords = 26

    private static let coachingInstruction = """
    Write today's coaching line for my home screen, using the TODAY VS BASELINE block first and the rest \
    of the data only for context.
    Rules:
    - ONE sentence, at most 20 words. No greeting, no Markdown, no emoji, no hedging ("might", "consider").
    - Name the single most telling signal today against my 7- and 30-day averages (e.g. HRV well below \
    normal, short sleep, a big effort yesterday, charge above usual) and cite at most one number.
    - Then give one concrete call for today: push hard, a normal session, easy zone 2 only, or rest - \
    plus a specific bedtime or sleep target when sleep is the problem.
    - If everything is near baseline, say so and recommend a normal training day.
    - Light pirate flavour: at most one pirate word ("arr", "matey", "ship-shape"), the advice stays plain.
    """

    /// Bumped when what the line is written from changes, so the day's line is rewritten once. v2: written
    /// only from today's own scores after the night closes (`OpenNight`); v1 could be written from a
    /// carried Charge or a night still being recorded ("short sleep at 4.9h" on an 8.4 h night).
    private static let coachingVersion = "v2"

    /// Today's line: the cached one, or — once `charge` and `rest` are both known — one request per day.
    func coachingLine(dayKey: String, charge: Double?, rest: Double?) async -> String? {
        let fingerprint = dayKey + "|" + Self.coachingVersion
        if let cached = cachedReply(slot: "today", fingerprint: fingerprint) { return cached }
        guard let charge, let rest else { return nil }   // scores not in yet — wait for the fresh ones
        return await cachedReply(slot: "today", fingerprint: fingerprint, prompt: {
            let digest = Self.coachingDigest(days: self.repo.days, dayKey: dayKey, charge: charge, rest: rest)
            return digest + "\n\n" + (await self.buildFullContext()) + "\n\n---\n\n" + Self.coachingInstruction
        }, accept: Self.shortenedCoachingLine)
    }

    // MARK: Pure helpers (unit-tested)

    /// Today's numbers beside their 7- and 30-day averages (today excluded from the averages), plus
    /// yesterday's effort — the comparison the line should be built on. `charge` / `rest` are the scores
    /// Today shows; HRV, resting HR and sleep hours come from today's row.
    static func coachingDigest(days: [DailyMetric], dayKey: String, charge: Double, rest: Double) -> String {
        let prior = days.filter { $0.day < dayKey }
        let week = Array(prior.suffix(7)), month = Array(prior.suffix(30))
        let today = days.last { $0.day == dayKey }

        func avg(_ rows: [DailyMetric], _ f: (DailyMetric) -> Double?) -> Double? {
            let v = rows.compactMap(f)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        func fmt(_ v: Double?, _ decimals: Int) -> String {
            guard let v else { return "—" }
            return String(format: "%.\(decimals)f", v)
        }
        func line(_ name: String, _ now: Double?, _ f: (DailyMetric) -> Double?, _ decimals: Int, _ unit: String) -> String {
            "  \(name): \(fmt(now, decimals))\(unit) (7d avg \(fmt(avg(week, f), decimals)), 30d avg \(fmt(avg(month, f), decimals)))"
        }

        let sleepH: (DailyMetric) -> Double? = { $0.totalSleepMin.map { $0 / 60 } }
        let yesterday = prior.last
        return [
            "TODAY VS BASELINE (\(dayKey)):",
            line("charge", charge, { $0.recovery }, 0, "%"),
            "  rest score: \(fmt(rest, 0))%",
            line("sleep", today.flatMap(sleepH), sleepH, 1, "h"),
            line("HRV", today?.avgHrv, { $0.avgHrv }, 0, " ms"),
            line("resting HR", today?.restingHr.map(Double.init), { $0.restingHr.map(Double.init) }, 0, " bpm"),
            "  yesterday's effort: \(fmt(yesterday?.strain, 1)) (7d avg \(fmt(avg(week, { $0.strain }), 1)))",
        ].joined(separator: "\n")
    }

    /// The reply as one short line: whitespace collapsed, quotes and Markdown emphasis stripped, cut to the
    /// first sentence when the model ran long, and hard-capped at `coachingMaxWords`. nil when empty.
    static func shortenedCoachingLine(_ reply: String) -> String? {
        var text = reply.replacingOccurrences(of: "*", with: "")
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' "))
        guard !text.isEmpty else { return nil }
        if text.split(separator: " ").count > coachingMaxWords,
           let end = text.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            text = String(text[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        let words = text.split(separator: " ")
        if words.count > coachingMaxWords {
            text = words.prefix(coachingMaxWords).joined(separator: " ") + "…"
        }
        return text
    }
}
