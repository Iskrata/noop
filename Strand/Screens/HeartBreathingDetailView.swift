import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign

/// Fork: one screen's history — irregular rhythm over 14 days, or breathing disturbances over 30 nights —
/// opened from Lab → Heart & Breathing and from the Today banner.
struct HeartBreathingDetailView: View {
    enum Kind: String, Identifiable {
        case rhythm, breathing
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .rhythm ? "Irregular rhythm" : "Breathing disturbances" }
        var symbol: String { self == .rhythm ? "waveform.path.ecg" : "lungs.fill" }
    }

    let kind: Kind
    @ObservedObject private var hb = HeartBreathingStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    NoopCard { HeartBreathingSummary(kind: kind) }
                    if kind == .rhythm { rhythmChart } else { breathingChart }
                    history
                    Text(kind == .rhythm ? Self.rhythmMethod : Self.breathingMethod)
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, NoopMetrics.screenHPadding)
                .padding(.vertical, 16)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    // MARK: - Charts

    private var rhythmDays: [(day: String, value: HeartBreathingStore.RhythmDay)] {
        (0..<HeartBreathingPatterns.rhythmWindowDays).reversed().compactMap { ago in
            let d = HeartBreathingStore.dayKey(daysAgo: ago)
            return hb.rhythm[d].map { (d, $0) }
        }
    }

    private var nights: [(day: String, value: HeartBreathingStore.BreathingNight)] {
        (0..<HeartBreathingPatterns.breathingWindowDays).reversed().compactMap { ago in
            let d = HeartBreathingStore.dayKey(daysAgo: ago)
            return hb.breathing[d].map { (d, $0) }
        }
    }

    private var rhythmChart: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Irregular minutes per day").strandOverline()
                Chart(rhythmDays, id: \.day) { d in
                    BarMark(x: .value("Day", Self.shortDay(d.day)), y: .value("Minutes", d.value.irregularMinutes))
                        .foregroundStyle(d.value.episodes > 0 ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                }
                .frame(height: 140)
            }
        }
    }

    private var breathingChart: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Disturbances per hour").strandOverline()
                Chart {
                    ForEach(nights, id: \.day) { n in
                        BarMark(x: .value("Night", Self.shortDay(n.day)), y: .value("Per hour", n.value.index))
                            .foregroundStyle(n.value.index >= CvhrDetector.elevatedIndex
                                             ? StrandPalette.statusWarning : StrandPalette.accent)
                    }
                    RuleMark(y: .value("Elevated", CvhrDetector.elevatedIndex))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
            }
        }
    }

    // MARK: - History

    private var history: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind == .rhythm ? "Last 14 days" : "Last 30 nights").strandOverline()
                if kind == .rhythm {
                    if rhythmDays.isEmpty { empty }
                    ForEach(rhythmDays.reversed(), id: \.day) { d in
                        row(Self.longDay(d.day), Self.rhythmLine(d.value), flagged: d.value.episodes > 0)
                    }
                } else {
                    if nights.isEmpty { empty }
                    ForEach(nights.reversed(), id: \.day) { n in
                        row(Self.longDay(n.day),
                            String(format: "%.1f/h over %.1f h", n.value.index, n.value.readableHours),
                            flagged: n.value.index >= CvhrDetector.elevatedIndex)
                    }
                }
            }
        }
    }

    private var empty: some View {
        Text("Nothing read yet. Results appear after the next sync.")
            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
    }

    private func row(_ day: String, _ value: String, flagged: Bool) -> some View {
        HStack {
            Text(day).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Text(value).font(StrandFont.captionNumber)
                .foregroundStyle(flagged ? StrandPalette.statusWarning : StrandPalette.textSecondary)
        }
    }

    private static func rhythmLine(_ d: HeartBreathingStore.RhythmDay) -> String {
        let read = String(format: "%.1f h read", Double(d.readableMinutes) / 60)
        guard d.episodes > 0 else { return "\(read) · \(d.irregularMinutes) irregular min" }
        let start = d.firstEpisodeStart.map {
            " from " + Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .omitted, time: .shortened)
        } ?? ""
        return "\(d.episodes == 1 ? "1 episode" : "\(d.episodes) episodes"), \(d.episodeMinutes) min\(start)"
    }

    private static func date(_ day: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: day)
    }
    private static func shortDay(_ day: String) -> String {
        date(day)?.formatted(.dateTime.day().month(.defaultDigits)) ?? day
    }
    private static func longDay(_ day: String) -> String {
        date(day)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? day
    }

    private static let rhythmMethod = "Read from your strap's beat-to-beat intervals while your wrist is still, using a published atrial-fibrillation detector (Petrėnas 2015). An episode is 30+ minutes of irregular rhythm. Tested on PhysioNet recordings with your strap's noise added: 15 of 16 people with AF flagged, 0–1 of 54 healthy people. It can't see atrial flutter with a regular beat, and frequent extra beats can look irregular. A screening estimate, not a diagnosis."
    private static let breathingMethod = "Counts the repeating heart-rate swings that breathing pauses leave during sleep (Hayano's CVHR method), per hour of still, readable sleep. Tested on PhysioNet sleep-apnea recordings with your strap's noise added: 12–13 of 18 people with sleep apnea flagged at 5/h, none of 12 normal sleepers. It can't tell obstructive from central apnea and misses mild, hypopnea-heavy cases. A screening estimate, not a diagnosis."
}

/// The one-line state of a screen, shared by the Lab card and the detail header.
struct HeartBreathingSummary: View {
    let kind: HeartBreathingDetailView.Kind
    @ObservedObject private var hb = HeartBreathingStore.shared

    var body: some View {
        let (headline, detail, flagged) = text
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(flagged ? StrandPalette.statusWarning : StrandPalette.accent)
                .frame(width: 30, height: 30)
                .background((flagged ? StrandPalette.statusWarning : StrandPalette.accent).opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(detail).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: (String, String, Bool) {
        switch kind {
        case .rhythm:
            let p = hb.rhythmPattern
            let since = HeartBreathingStore.dayKey(daysAgo: HeartBreathingPatterns.rhythmWindowDays - 1)
            let hours = Double(hb.rhythm.filter { $0.key >= since }.map(\.value.readableMinutes).reduce(0, +)) / 60
            let read = String(format: "%.0f h of still-wrist rhythm read in 14 days.", hours)
            if p.repeating {
                return ("Irregular rhythm on \(p.daysWithEpisodes.count) days", "A repeating pattern that can point to atrial fibrillation. \(read)", true)
            }
            if p.daysWithEpisodes.count == 1 {
                return ("One irregular episode", "One day in 14 isn't a pattern yet. \(read)", false)
            }
            return ("No irregular rhythm", read, false)
        case .breathing:
            let p = hb.breathingPattern
            let last = hb.breathing.max { $0.key < $1.key }
            let lastText = last.map { String(format: "Last night %.1f/h.", $0.value.index) } ?? "No night read yet."
            if p.repeating {
                return ("Elevated on \(p.elevatedNights) of \(p.readableNights) nights",
                        "A repeating pattern seen with sleep apnea. \(lastText)", true)
            }
            let need = max(0, HeartBreathingPatterns.breathingMinNights - p.readableNights)
            let counted = p.elevatedNights == 0 ? "None of \(p.readableNights) nights elevated."
                : "\(p.elevatedNights) of \(p.readableNights) nights elevated."
            let base = "\(counted) \(lastText)"
            return (p.elevatedNights == 0 ? "Breathing looks normal" : "Some elevated nights",
                    need > 0 ? "\(base) \(need) more nights before the pattern check." : base, false)
        }
    }
}
