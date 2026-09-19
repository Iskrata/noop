import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopProtocol
import WhoopStore

/// The heading every liquid Today section uses: a tracked overline title and a trailing caption.
struct LiquidSectionHead: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(title)).font(StrandFont.overline).tracking(1.6).foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            Text(LocalizedStringKey(trailing)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
    }
}

/// Fork: WHOOP's "Today's Activities" under the three scores — the night's sleep, every workout and every
/// auto-detected bout of the selected day, each with the Effort it earned and its share of the day
/// (`DayActivities`). A detected bout can be saved as a workout or dismissed from its row.
struct DayActivitiesSection: View {
    /// The day window `LiquidTodayView.load()` resolved (calendar or day-cycle), inclusive.
    let window: ClosedRange<Int>
    let workouts: [WorkoutRow]
    let dayEffort: Double?
    let restingHR: Double?
    /// The night's Rest score (sleep performance), shown on the main sleep row.
    let restScore: Double?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(CardAppearancePrefs.opacityKey) private var cardOpacityPercent = CardAppearancePrefs.defaultPercent
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(ScoreVisibility.hiddenKey) private var scoresHidden = true

    @State private var activities: [DayActivity] = []
    @State private var pendingDetected: DetectedWorkout?

    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    var body: some View {
        VStack(spacing: 8) {
            LiquidSectionHead(title: "ACTIVITIES", trailing: trailingCaption)
            VStack(spacing: 0) {
                if activities.isEmpty {
                    Text("No activities yet")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 { Divider().opacity(0.4) }
                    row(activity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoopPanelSurface(cornerRadius: 22,
                                         surfaceOpacity: max(0, min(1, Double(cardOpacityPercent) / 100))))
        }
        .task(id: LoadKey(window: window, seq: repo.refreshSeq, workouts: workouts.map(\.startTs),
                          dayEffort: dayEffort, restingHR: restingHR)) {
            await load()
        }
        .confirmationDialog("Auto-detected activity", isPresented: Binding(
            get: { pendingDetected != nil }, set: { if !$0 { pendingDetected = nil } }
        ), presenting: pendingDetected) { bout in
            Button("Save as workout") { Task { await save(bout) } }
            Button("Not a workout", role: .destructive) { dismiss(bout) }
        }
    }

    private var trailingCaption: String {
        let count = activities.count
        return count == 1 ? String(localized: "1 activity") : String(localized: "\(count) activities")
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ activity: DayActivity) -> some View {
        switch activity.kind {
        case .sleep(let night):
            NavigationLink(value: TabRoute.sleep) {
                rowBody(icon: "moon.fill", tint: StrandPalette.restColor, title: String(localized: "Sleep"),
                        subtitle: timeRange(activity), badge: nil,
                        value: sleepValue(night), frac: nil)
            }
            .buttonStyle(.plain)
        case .workout(let w):
            NavigationLink(value: TabRoute.workouts) {
                rowBody(icon: sportSymbol(w.sport), tint: StrandPalette.effortColor,
                        title: WorkoutSource.displaySport(w.sport), subtitle: timeRange(activity), badge: nil,
                        value: effortValue(activity, fallbackKcal: w.energyKcal, fallbackHr: w.avgHr),
                        frac: activity.effort.map { $0 / 100 })
            }
            .buttonStyle(.plain)
        case .detected(let bout):
            Button { pendingDetected = bout } label: {
                rowBody(icon: "figure.run", tint: StrandPalette.effortColor, title: String(localized: "Activity"),
                        subtitle: timeRange(activity), badge: String(localized: "AUTO"),
                        value: effortValue(activity, fallbackKcal: nil, fallbackHr: bout.avgBpm),
                        frac: activity.effort.map { $0 / 100 })
            }
            .buttonStyle(.plain)
        }
    }

    private func rowBody(icon: String, tint: Color, title: String, subtitle: String, badge: String?,
                         value: (main: String, caption: String), frac: Double?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(StrandFont.number(15)).foregroundStyle(StrandPalette.textPrimary)
                    if let badge {
                        Text(badge).font(StrandFont.overlineScaled(8)).tracking(1)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.18)))
                            .foregroundStyle(tint)
                    }
                }
                Text(subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                if let frac, !scoresHidden {
                    LiquidTube(frac: max(0, min(1, frac)), tint: tint, height: 6, animated: false)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value.main).font(StrandFont.number(17)).foregroundStyle(StrandPalette.textPrimary)
                Text(value.caption).font(StrandFont.overlineScaled(9)).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Values

    /// Effort + share of the day; with scores hidden, the raw measurement behind it (kcal, else avg HR).
    private func effortValue(_ a: DayActivity, fallbackKcal: Double?, fallbackHr: Int?) -> (main: String, caption: String) {
        if scoresHidden {
            if let kcal = fallbackKcal { return (String(Int(kcal.rounded())), String(localized: "KCAL")) }
            if let hr = fallbackHr { return (String(hr), String(localized: "AVG HR")) }
            return ("–", "")
        }
        guard let effort = a.effort else { return ("–", String(localized: "EFFORT")) }
        let caption = a.share.map { String(localized: "\(Int(($0 * 100).rounded()))% OF DAY") }
            ?? String(localized: "EFFORT")
        return (UnitFormatter.effortDisplay(effort, scale: effortScale), caption)
    }

    private func sleepValue(_ night: CachedSleepSession) -> (main: String, caption: String) {
        let minutes = max(0, night.endTs - night.effectiveStartTs) / 60
        let duration = String(format: "%d:%02d", minutes / 60, minutes % 60)
        if !scoresHidden, let rest = restScore, isMainNight(night) {
            return ("\(Int(rest.rounded()))%", String(localized: "REST · \(duration)"))
        }
        return (duration, String(localized: "HOURS"))
    }

    /// The day's longest block carries the Rest score; naps show only their duration.
    private func isMainNight(_ night: CachedSleepSession) -> Bool {
        let sleeps = activities.compactMap { a -> CachedSleepSession? in
            if case .sleep(let s) = a.kind { return s } else { return nil }
        }
        return sleeps.max { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) } == night
    }

    private func timeRange(_ a: DayActivity) -> String {
        let f = AppClock.hourMinuteFormatter()
        let start = f.string(from: Date(timeIntervalSince1970: TimeInterval(a.startTs)))
        let end = f.string(from: Date(timeIntervalSince1970: TimeInterval(a.endTs)))
        let minutes = max(0, a.endTs - a.startTs) / 60
        return "\(start)–\(end) · \(minutes) min"
    }

    // MARK: Data

    private struct LoadKey: Equatable {
        let window: ClosedRange<Int>
        let seq: Int
        let workouts: [Int]
        let dayEffort: Double?
        let restingHR: Double?
    }

    private func load() async {
        let from = window.lowerBound, to = window.upperBound
        // A night that started before the window opens (calendar mode) still ends inside it, so read
        // blocks from 18 h earlier and keep the ones that END in the window.
        var blocks = await repo.sleepSessions(from: from - 18 * 3600, to: to)
        if blocks.isEmpty { blocks = await repo.computedSleepSessions(from: from - 18 * 3600, to: to) }
        let hr = await repo.hrSamples(from: from, to: to, limit: 200_000)
        let detected = await repo.detectedActivities(from: from, to: to, hr: hr)
        let scoring = DayActivities.Scoring(
            maxHR: profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil,
            restingHR: restingHR ?? StrainScorer.defaultRestingHR,
            method: PuffinExperiment.effortMethod, sex: profile.sex)
        let built = DayActivities.build(
            sleeps: DayActivities.sleepsEnding(in: blocks, from: from, to: to),
            workouts: workouts, detected: detected, hr: hr, dayEffort: dayEffort, scoring: scoring)
        guard !Task.isCancelled else { return }
        activities = built
    }

    private func save(_ bout: DetectedWorkout) async {
        pendingDetected = nil
        _ = await repo.saveDetectedWorkout(bout)
        await repo.refresh()
    }

    private func dismiss(_ bout: DetectedWorkout) {
        repo.dismissDetectedSuggestion(bout)
        pendingDetected = nil
        activities.removeAll { if case .detected(let d) = $0.kind { return d == bout } else { return false } }
    }
}
