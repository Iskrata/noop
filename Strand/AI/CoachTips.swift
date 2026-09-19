import Foundation
import StrandImport
import WhoopStore

/// Fork: actionable Coach tips — one set per lab report (Biology) and one per day for sleep (Sleep screen).
/// Both go through the once-only reply cache (`CoachReplies.swift`): a report's tips are requested once and
/// kept until its values change; the sleep tips once per wake day, after last night is scored.
extension AICoachEngine {

    // MARK: Lab report

    private static let labInstruction = """
    Above is one of my blood test reports with each result, the range printed on the report, whether it is \
    in range, and my previous result when I have one. Give me actionable tips for THIS report.
    Rules:
    - At most 4 tips, one per line, each starting with "- ", a verb, at most 24 words. Nothing else.
    - Only for results that are out of range, sitting at the edge of their range, or moving the wrong way \
    since my last test. Name the marker in each tip.
    - Be concrete: specific foods and portions, type and weekly amount of exercise, sleep, alcohol, \
    hydration, or when to retest. Use my training data for context.
    - When a result deserves a doctor's look, make that its own tip, plainly. No diagnosis, no prescription drugs.
    - If everything is comfortably in range, give one line saying so and one habit worth keeping.
    """

    /// Tips for the report taken on `day` (rows: every Lab Book reading, any day — earlier ones give trend).
    func labReportTips(day: String, rows: [LabMarkerRow], sex: String, name: @escaping (String) -> String) async -> [String]? {
        let fingerprint = Self.labFingerprint(day: day, rows: rows)
        let reply = await cachedReply(slot: "labs:" + day, fingerprint: fingerprint, prompt: {
            // Today's training data only describes a recent report; an old one gets the report alone.
            let context = Self.isRecentReport(day) ? self.buildContext()
                : "This report is from \(day); my current wearable data does not describe that time, so ignore training context."
            return Self.labReportDigest(day: day, rows: rows, sex: sex, name: name)
                + "\n\n" + context + "\n\n---\n\n" + Self.labInstruction
        })
        return reply.map { Self.tipLines($0) }
    }

    /// The cached tips for a report, without requesting.
    func cachedLabReportTips(day: String, rows: [LabMarkerRow]) -> [String]? {
        cachedReply(slot: "labs:" + day, fingerprint: Self.labFingerprint(day: day, rows: rows)).map { Self.tipLines($0) }
    }

    /// True for a report taken within the last 60 days.
    static func isRecentReport(_ day: String, now: Date = Date()) -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return false }
        return now.timeIntervalSince(date) < 60 * 86_400
    }

    static func labFingerprint(day: String, rows: [LabMarkerRow]) -> String {
        rows.filter { $0.day == day }
            .map { "\($0.markerKey)=\($0.value.map { String($0) } ?? $0.valueText ?? "")" }
            .sorted().joined(separator: ";")
    }

    /// One line per result on `day`: value, the report's range and where the value sits, and the previous reading.
    static func labReportDigest(day: String, rows: [LabMarkerRow], sex: String, name: (String) -> String) -> String {
        let byKey = Dictionary(grouping: rows, by: \.markerKey)
        let lines: [String] = rows.filter { $0.day == day }
            .sorted { name($0.markerKey) < name($1.markerKey) }
            .map { row in
                let value = row.valueText ?? row.value.map { LabScanFormat.plain($0) } ?? "—"
                var parts = ["  \(name(row.markerKey)): \(value) \(row.unit)".trimmingCharacters(in: .whitespaces)]
                if let ref = row.referenceText {
                    var status = "range not read"
                    if let v = row.value, let range = LabReferenceRange.parse(ref, sex: sex) {
                        switch range.status(v) {
                        case .inRange: status = "in range"
                        case .below:   status = "BELOW range"
                        case .above:   status = "ABOVE range"
                        }
                    }
                    parts.append("range \(ref), \(status)")
                }
                if let previous = byKey[row.markerKey]?.filter({ $0.day < day }).max(by: { $0.day < $1.day }),
                   let pv = previous.value, previous.unit == row.unit {
                    parts.append("previous \(LabScanFormat.plain(pv)) on \(previous.day)")
                }
                return parts.joined(separator: "; ")
            }
        let patient = sex.lowercased().hasPrefix("f") ? "female" : "male"
        return (["BLOOD TEST REPORT \(day) (patient: \(patient)):"] + lines).joined(separator: "\n")
    }

    // MARK: Sleep week

    private static let sleepInstruction = """
    Above are my last nights of sleep. Give me actionable tips to raise my sleep score next week.
    Rules:
    - At most 3 tips, one per line, each starting with "- ", a verb, at most 24 words. Nothing else.
    - Lead with the biggest lever. My score weighs hours vs need, bed/wake consistency and efficiency.
    - Tie each tip to a number from the data (e.g. "bedtimes span 1h50", "6.4h vs 8.1h need", "efficiency 84%").
    - Be concrete: a target bedtime and wake time from my own pattern, caffeine cutoff, alcohol, late training, \
    wind-down, bedroom temperature, naps.
    - If sleep is already strong, say so in one line and name the one thing to protect.
    """

    /// Tips for the week ending on `wakeDay` (the latest scored night).
    func sleepWeekTips(wakeDay: String) async -> [String]? {
        let reply = await cachedReply(slot: "sleep", fingerprint: wakeDay, prompt: {
            let to = Int(Date().timeIntervalSince1970), from = to - 8 * 86_400
            var sessions = await self.repo.sleepSessions(from: from, to: to)
            if sessions.isEmpty { sessions = await self.repo.computedSleepSessions(from: from, to: to) }
            let digest = Self.sleepWeekDigest(days: self.repo.days, sessions: sessions,
                                              needHours: PersonalSleepScore.needHours(),
                                              score: { PersonalSleepScore.composite($0) },
                                              consistency: { PersonalSleepScore.consistency(day: $0) })
            return digest + "\n\n---\n\n" + Self.sleepInstruction
        })
        return reply.map { Self.tipLines($0, max: 3) }
    }

    func cachedSleepWeekTips(wakeDay: String) -> [String]? {
        cachedReply(slot: "sleep", fingerprint: wakeDay).map { Self.tipLines($0, max: 3) }
    }

    /// The last 7 nights: bed/wake (local), hours vs need, efficiency, stages, score, consistency, HRV, RHR,
    /// next-day charge — then the spreads and averages the tips should lean on.
    static func sleepWeekDigest(days: [DailyMetric], sessions: [CachedSleepSession], needHours: Double,
                                score: (DailyMetric) -> Double?, consistency: (String) -> Double?,
                                calendar: Calendar = .current) -> String {
        let keyFormatter = DateFormatter()
        keyFormatter.calendar = calendar
        keyFormatter.timeZone = calendar.timeZone
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.dateFormat = "yyyy-MM-dd"
        // Main sleep per wake day: the longest session ending that day.
        var main: [String: CachedSleepSession] = [:]
        for s in sessions {
            let day = keyFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(s.endTs)))
            if let cur = main[day], cur.endTs - cur.effectiveStartTs >= s.endTs - s.effectiveStartTs { continue }
            main[day] = s
        }
        func clock(_ ts: Int) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        /// Minutes on a clock that runs from noon, so 23:30 and 00:30 are 60 apart.
        func noonMinutes(_ ts: Int) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return Double(((c.hour ?? 0) + 12) % 24 * 60 + (c.minute ?? 0))
        }
        func h(_ minutes: Double?) -> String { minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—" }
        func span(_ v: [Double]) -> String {
            guard let lo = v.min(), let hi = v.max() else { return "—" }
            let m = Int(hi - lo)
            return "\(m / 60)h\(String(format: "%02d", m % 60))"
        }

        let week = Array(days.filter { main[$0.day] != nil || $0.totalSleepMin != nil }.suffix(7))
        var lines = ["SLEEP, LAST \(week.count) NIGHTS (need \(String(format: "%.1f", needHours))h):"]
        var bedMinutes: [Double] = [], wakeMinutes: [Double] = []
        for d in week {
            var parts: [String] = []
            if let s = main[d.day] {
                parts.append("bed \(clock(s.effectiveStartTs)) wake \(clock(s.endTs))")
                bedMinutes.append(noonMinutes(s.effectiveStartTs))
                wakeMinutes.append(noonMinutes(s.endTs))
            }
            parts.append("asleep \(h(d.totalSleepMin))")
            if let e = d.efficiency { parts.append("eff \(Int((e <= 1 ? e * 100 : e).rounded()))%") }
            parts.append("deep \(h(d.deepMin)) REM \(h(d.remMin))")
            if let sc = score(d) { parts.append("sleep score \(Int(sc.rounded()))%") }
            if let c = consistency(d.day) { parts.append("consistency \(Int(c.rounded()))%") }
            if let hrv = d.avgHrv { parts.append("HRV \(Int(hrv.rounded()))") }
            if let rhr = d.restingHr { parts.append("RHR \(rhr)") }
            if let charge = d.recovery { parts.append("charge \(Int(charge.rounded()))%") }
            if let effort = d.strain { parts.append("effort \(String(format: "%.1f", effort))") }
            lines.append("  \(d.day): " + parts.joined(separator: ", "))
        }
        let asleep = week.compactMap(\.totalSleepMin)
        let avgAsleep = asleep.isEmpty ? nil : asleep.reduce(0, +) / Double(asleep.count)
        lines.append("  average asleep \(h(avgAsleep)) vs need \(String(format: "%.1f", needHours))h; "
                     + "bedtimes span \(span(bedMinutes)); wake times span \(span(wakeMinutes))")
        return lines.joined(separator: "\n")
    }
}

/// Plain number text for prompts: up to 3 decimals, trailing zeros dropped (POSIX, locale-free).
enum LabScanFormat {
    static func plain(_ v: Double) -> String { LabBookFormat.plain(v) }
}
