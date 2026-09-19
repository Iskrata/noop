import Foundation
import WhoopStore

/// Fork: the one-sentence COACHING line under Today's rings (Bevel's). Generated ONCE per logical day, the
/// first time both of today's scores (Charge and Rest) are in, then served from a cache for the rest of the
/// day — reopening the app, a later rescore or a growing Effort never spends another request. A failed call
/// is retried at most every 30 minutes. nil means "use the on-device line".
extension AICoachEngine {

    static let coachingCacheKey = "fork.coachingLine.v2"
    private static let coachingAttemptKey = "fork.coachingLine.lastAttempt"
    private static let coachingRetrySeconds: TimeInterval = 30 * 60
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

    /// The cached line when it was generated for `dayKey`.
    func cachedCoachingLine(dayKey: String) -> String? {
        guard let cached = UserDefaults.standard.dictionary(forKey: Self.coachingCacheKey),
              cached["day"] as? String == dayKey else { return nil }
        return cached["text"] as? String
    }

    /// Today's line: the cache, or — once `charge` and `rest` are both known — one request. Concurrent
    /// callers for the same day share the in-flight request.
    func coachingLine(dayKey: String, charge: Double?, rest: Double?) async -> String? {
        if let cached = cachedCoachingLine(dayKey: dayKey) { return cached }
        guard let charge, let rest else { return nil }   // scores not in yet — wait for the fresh ones
        guard CoachBriefScheduler.coachMasterEnabled, isConfigured, dataConsent, let key = resolvedKey else {
            return nil
        }
        if let task = coachingInFlight[dayKey] { return await task.value }
        let lastAttempt = UserDefaults.standard.double(forKey: Self.coachingAttemptKey)
        guard Date().timeIntervalSince1970 - lastAttempt > Self.coachingRetrySeconds else { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.coachingAttemptKey)

        let task = Task<String?, Never> {
            let digest = Self.coachingDigest(days: repo.days, dayKey: dayKey, charge: charge, rest: rest)
            let context = await buildFullContext()
            let wire: [(role: ChatMessage.Role, content: String)] =
                [(.user, digest + "\n\n" + context + "\n\n---\n\n" + Self.coachingInstruction)]
            do {
                let reply = try await callProvider(key: key, messages: wire)
                guard let line = Self.shortenedCoachingLine(reply) else { return nil }
                UserDefaults.standard.set(["day": dayKey, "text": line], forKey: Self.coachingCacheKey)
                NSLog("Coach: coaching line generated for %@", dayKey)
                return line
            } catch {
                NSLog("Coach: coaching line failed - \(error.localizedDescription)")
                return nil
            }
        }
        coachingInFlight[dayKey] = task
        let line = await task.value
        coachingInFlight[dayKey] = nil
        return line
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
