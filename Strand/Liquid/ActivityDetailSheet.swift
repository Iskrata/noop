import SwiftUI
import Charts
import StrandDesign
import WhoopStore

/// Fork: the drawer a Today Activities row opens — the activity's heart rate over its own window with its
/// duration, average/max HR and Effort. A detected bout also gets its Save / Not-a-workout actions here.
struct ActivityDetailSheet: View {
    let activity: DayActivity
    let title: String
    let effortText: String?
    /// Detected bouts only: save through the manual-workout sheet, or dismiss.
    var onSave: (() -> Void)? = nil
    var onDismissBout: (() -> Void)? = nil

    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var buckets: [HRBucket] = []

    private var source: String {
        if case .workout(let w) = activity.kind { return w.source }
        return ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(timeRange).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: 22) {
                        stat("DURATION", RawMetricHeroCell.hoursMinutes(Double(max(0, activity.endTs - activity.startTs)) / 60))
                        stat("AVG HR", avgHr.map { "\($0)" } ?? "–")
                        stat("MAX HR", maxHr.map { "\($0)" } ?? "–")
                        if let effortText { stat("EFFORT", effortText) }
                    }
                    chart
                    if onSave != nil || onDismissBout != nil {
                        HStack(spacing: 12) {
                            if let onSave {
                                Button { dismiss(); onSave() } label: { Label("Save as workout…", systemImage: "checkmark") }
                                    .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                            }
                            if let onDismissBout {
                                Button("Not a workout", role: .destructive) { dismiss(); onDismissBout() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            buckets = await repo.workoutHrBuckets(from: activity.startTs, to: activity.endTs, source: source)
        }
    }

    private var avgHr: Int? {
        buckets.isEmpty ? nil : Int((buckets.map(\.bpm).reduce(0, +) / Double(buckets.count)).rounded())
    }
    private var maxHr: Int? { buckets.map(\.bpm).max().map { Int($0.rounded()) } }

    @ViewBuilder
    private var chart: some View {
        if buckets.count >= 2 {
            Chart(buckets, id: \.ts) { b in
                AreaMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(b.ts))),
                         y: .value("BPM", b.bpm))
                    .foregroundStyle(LinearGradient(colors: [StrandPalette.liquidHeart.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", Date(timeIntervalSince1970: TimeInterval(b.ts))),
                         y: .value("BPM", b.bpm))
                    .foregroundStyle(StrandPalette.liquidHeart)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: 220)
        } else {
            Text("No strap heart rate for this activity")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var timeRange: String {
        let f = AppClock.hourMinuteFormatter()
        return "\(f.string(from: Date(timeIntervalSince1970: TimeInterval(activity.startTs))))–"
            + f.string(from: Date(timeIntervalSince1970: TimeInterval(activity.endTs)))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label)).font(StrandFont.overline).tracking(1.2).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.number(18)).foregroundStyle(StrandPalette.textPrimary)
        }
    }
}
