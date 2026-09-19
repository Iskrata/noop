import Foundation

/// Fork: one cached, once-only Coach request per "slot" — Today's coaching line, a lab report's tips, the week's
/// sleep tips. A slot's reply is reused until its `fingerprint` (the day, or the report's values) changes, so
/// opening a screen never spends a request by itself; concurrent callers share one in-flight request; a failed
/// call is retried at most every 30 minutes. nil when the Coach is off / unconfigured / without data consent.
extension AICoachEngine {

    private static let repliesKey = "fork.coachReplies.v1"
    private static let attemptsKey = "fork.coachReplies.attempts"
    private static let retrySeconds: TimeInterval = 30 * 60

    /// True when the Coach may send the user's data (master switch, a configured provider, data consent).
    var canSendCoachData: Bool {
        CoachBriefScheduler.coachMasterEnabled && isConfigured && dataConsent && resolvedKey != nil
    }

    /// The cached reply for `slot` when it was generated for `fingerprint`.
    func cachedReply(slot: String, fingerprint: String) -> String? {
        let all = UserDefaults.standard.dictionary(forKey: Self.repliesKey) as? [String: [String: String]]
        guard let entry = all?[slot], entry["fp"] == fingerprint else { return nil }
        return entry["text"]
    }

    /// The cached reply, or one request built by `prompt` (only called when a request is actually made).
    /// `accept` post-processes the reply; returning nil rejects it (nothing cached).
    func cachedReply(slot: String, fingerprint: String, prompt: @escaping () async -> String,
                     accept: @escaping (String) -> String? = { $0 }) async -> String? {
        if let cached = cachedReply(slot: slot, fingerprint: fingerprint) { return cached }
        guard canSendCoachData, let key = resolvedKey else { return nil }
        let flight = slot + "\u{1}" + fingerprint
        if let task = coachingInFlight[flight] { return await task.value }
        var attempts = UserDefaults.standard.dictionary(forKey: Self.attemptsKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        if let last = attempts[flight], now - last < Self.retrySeconds { return nil }
        attempts[flight] = now
        UserDefaults.standard.set(attempts.filter { now - $0.value < 86_400 }, forKey: Self.attemptsKey)

        let task = Task<String?, Never> {
            let wire: [(role: ChatMessage.Role, content: String)] = [(.user, await prompt())]
            do {
                let reply = try await callProvider(key: key, messages: wire)
                guard let text = accept(reply.trimmingCharacters(in: .whitespacesAndNewlines)), !text.isEmpty else {
                    return nil
                }
                var all = UserDefaults.standard.dictionary(forKey: Self.repliesKey) as? [String: [String: String]] ?? [:]
                all[slot] = ["fp": fingerprint, "text": text]
                UserDefaults.standard.set(all, forKey: Self.repliesKey)
                NSLog("Coach: %@ generated", slot)
                return text
            } catch {
                NSLog("Coach: %@ failed - \(error.localizedDescription)", slot)
                return nil
            }
        }
        coachingInFlight[flight] = task
        let text = await task.value
        coachingInFlight[flight] = nil
        return text
    }

    /// "- tip" / "• tip" / "1. tip" lines → tips (Markdown emphasis stripped). At most `max`.
    static func tipLines(_ reply: String, max: Int = 4) -> [String] {
        reply.components(separatedBy: .newlines).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
            guard !line.isEmpty else { return nil }
            if let r = line.range(of: #"^(?:[-•*]|\d+[.)])\s*"#, options: .regularExpression) {
                line.removeSubrange(r)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? nil : line
        }
        .prefix(max).map { $0 }
    }
}
