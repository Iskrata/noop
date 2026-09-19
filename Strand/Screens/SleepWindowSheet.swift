import SwiftUI
import Charts
import StrandDesign
import WhoopStore

// MARK: - Sleep window candles (fork)
//
// Tapping the Today Consistency card opens this: the last 7 nights as candles from bedtime to wake on a
// clock axis, with the week's average bedtime and wake as dashed guides, so drift is visible at a glance.

/// One night's main sleep block, placed on a clock axis measured in minutes since noon of the day before
/// the wake day (so 22:00 → 600, 07:30 → 1170, and a night never wraps midnight).
struct SleepWindowNight: Identifiable, Equatable {
    let wakeDay: Date
    let bedMinute: Double
    let wakeMinute: Double
    var id: Date { wakeDay }
}

enum SleepWindow {
    /// The main (longest) block per wake day for the `count` most recent wake days that have one, oldest
    /// first. `calendar` sets the local day boundaries.
    static func nights(from blocks: [CachedSleepSession], count: Int = 7,
                       calendar: Calendar = .current) -> [SleepWindowNight] {
        var mainByDay: [Date: CachedSleepSession] = [:]
        for b in blocks where b.endTs > b.effectiveStartTs {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(b.endTs)))
            if let current = mainByDay[day], current.endTs - current.effectiveStartTs >= b.endTs - b.effectiveStartTs {
                continue
            }
            mainByDay[day] = b
        }
        return mainByDay.keys.sorted().suffix(count).compactMap { day in
            guard let b = mainByDay[day],
                  let prevNoon = calendar.date(byAdding: .hour, value: -12, to: day) else { return nil }
            let origin = prevNoon.timeIntervalSince1970
            return SleepWindowNight(wakeDay: day,
                                    bedMinute: (TimeInterval(b.effectiveStartTs) - origin) / 60,
                                    wakeMinute: (TimeInterval(b.endTs) - origin) / 60)
        }
    }

    /// "23:40" for a minute on the noon-anchored axis.
    static func clockLabel(_ minute: Double) -> String {
        let m = ((Int(minute.rounded()) + 12 * 60) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

struct SleepWindowSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var nights: [SleepWindowNight] = []

    private var avgBed: Double? { nights.isEmpty ? nil : nights.map(\.bedMinute).reduce(0, +) / Double(nights.count) }
    private var avgWake: Double? { nights.isEmpty ? nil : nights.map(\.wakeMinute).reduce(0, +) / Double(nights.count) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let avgBed, let avgWake {
                    HStack(spacing: 24) {
                        stat("AVG BEDTIME", SleepWindow.clockLabel(avgBed))
                        stat("AVG WAKE", SleepWindow.clockLabel(avgWake))
                    }
                }
                if nights.isEmpty {
                    Text("No nights in the last week yet")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                } else {
                    chart
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Sleep window · 7 nights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            let now = Int(Date().timeIntervalSince1970)
            let from = now - 9 * 86_400
            var blocks = await repo.sleepSessions(from: from, to: now)
            if blocks.isEmpty { blocks = await repo.computedSleepSessions(from: from, to: now) }
            nights = SleepWindow.nights(from: blocks)
        }
    }

    private var chart: some View {
        let lo = (nights.map(\.bedMinute).min() ?? 600) - 60
        let hi = (nights.map(\.wakeMinute).max() ?? 1200) + 60
        return Chart {
            ForEach(nights) { n in
                BarMark(x: .value("Night", n.wakeDay, unit: .day),
                        yStart: .value("Bedtime", -n.bedMinute),
                        yEnd: .value("Wake", -n.wakeMinute),
                        width: .ratio(0.45))
                    .foregroundStyle(StrandPalette.restColor.gradient)
                    .clipShape(Capsule())
            }
            if let avgBed {
                RuleMark(y: .value("Avg bedtime", -avgBed))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            if let avgWake {
                RuleMark(y: .value("Avg wake", -avgWake))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        // Plotted negated so earlier clock times sit at the top, like a day planner.
        .chartYScale(domain: -hi ... -lo)
        .chartYAxis {
            AxisMarks(values: .stride(by: 120)) { value in
                AxisGridLine()
                AxisValueLabel { if let m = value.as(Double.self) { Text(SleepWindow.clockLabel(-m)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
            }
        }
        .frame(height: 320)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label)).font(StrandFont.overline).tracking(1.4).foregroundStyle(StrandPalette.textTertiary)
            Text(value).font(StrandFont.number(22)).foregroundStyle(StrandPalette.textPrimary)
        }
    }
}
