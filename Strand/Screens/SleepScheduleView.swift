import SwiftUI
import Charts
import StrandDesign
import WhoopStore

/// The last 7 nights' bedtimes and wake times as bars on a clock axis, with the averages and how far each
/// night strayed from them (`SleepSchedule`).
struct SleepScheduleView: View {
    @EnvironmentObject var repo: Repository

    private var schedule: SleepSchedule {
        SleepSchedule.build(sessions: repo.sleeps, now: Date(), offsetSec: TimeZone.current.secondsFromGMT())
    }

    var body: some View {
        let s = schedule
        ScreenScaffold(title: "Sleep Schedule", subtitle: "Bedtime and wake time, last 7 nights",
                       onRefresh: { await repo.refresh() },
                       topBackground: liquidScaffoldSky()) {
            if s.nights.isEmpty {
                ComingSoon(what: "No nights in the last week yet. Wear the strap overnight with NOOP connected.")
            } else {
                chart(s)
                summary(s)
            }
        }
    }

    // MARK: - Chart

    /// Bars run bedtime → wake downward: y is minutes after noon, negated so earlier times sit higher.
    private func chart(_ s: SleepSchedule) -> some View {
        let bed = s.nights.map { SleepSchedule.minutesAfterNoon($0.bedtime, offset) }
        let wake = s.nights.map { SleepSchedule.minutesAfterNoon($0.wake, offset) }
        let top = ((bed.min() ?? 600) / 60).rounded(.down) * 60 - 30
        let bottom = ((wake.max() ?? 1200) / 60).rounded(.up) * 60 + 30
        return ChartCard(title: "Sleep window", subtitle: String(localized: "Dashed lines mark your averages"),
                         height: 260) {
            Chart {
                ForEach(Array(s.nights.enumerated()), id: \.element.wakeDay) { i, night in
                    BarMark(x: .value("Night", weekday(night.wakeDay)),
                            yStart: .value("Bedtime", -bed[i]), yEnd: .value("Wake", -wake[i]), width: .ratio(0.45))
                        .foregroundStyle(StrandPalette.metricCyan.gradient)
                        .clipShape(Capsule())
                }
                if let avg = s.averageBedtimeMin {
                    RuleMark(y: .value("Average bedtime", -avg))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let avg = s.averageWakeMin {
                    RuleMark(y: .value("Average wake", -avg))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: -bottom ... -top)
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 120)) { value in
                    AxisGridLine().foregroundStyle(StrandPalette.textTertiary.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(SleepSchedule.clockLabel(minutesAfterNoon: -v))
                                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    // MARK: - Summary

    private func summary(_ s: SleepSchedule) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Consistency", overline: "Last 7 nights", trailing: verdict(s))
                HStack(alignment: .top) {
                    stat("Avg bedtime", s.averageBedtimeMin.map { SleepSchedule.clockLabel(minutesAfterNoon: $0) },
                         spread: s.bedtimeSpreadMin)
                    Spacer()
                    stat("Avg wake", s.averageWakeMin.map { SleepSchedule.clockLabel(minutesAfterNoon: $0) },
                         spread: s.wakeSpreadMin)
                }
                Text("Spread is how far a typical night strays from the average. Within about 30 minutes is a steady schedule.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ label: LocalizedStringKey, _ value: String?, spread: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).strandOverline()
            Text(value ?? "-").font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
            Text(spread.map { String(localized: "±\(Int($0.rounded())) min spread") } ?? String(localized: "Needs 2+ nights"))
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func verdict(_ s: SleepSchedule) -> String? {
        guard let bed = s.bedtimeSpreadMin, let wake = s.wakeSpreadMin else { return nil }
        let typical = (bed + wake) / 2
        if typical <= 30 { return String(localized: "Steady") }
        if typical <= 60 { return String(localized: "Somewhat variable") }
        return String(localized: "Irregular")
    }

    private var offset: Int { TimeZone.current.secondsFromGMT() }

    private func weekday(_ day: String) -> String {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: day) else { return day }
        let out = DateFormatter()
        out.timeZone = TimeZone(identifier: "UTC")
        out.setLocalizedDateFormatFromTemplate("EEE")
        return out.string(from: date)
    }
}
