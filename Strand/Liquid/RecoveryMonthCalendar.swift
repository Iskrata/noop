import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: the Today day picker as a month-at-a-glance recovery map (`MonthHeatCalendar`). Each day cell is
/// filled with `StrandPalette.recoveryColor` of that day's stored recovery (the same tint the Today Charge
/// ring uses), days with no score stay neutral, and chevrons step through previous months. Tapping a day still
/// jumps Today to it, so this replaces the plain graphical `DatePicker` without losing that job.
/// Numbers appear in the cells only when scores are not hidden (`ScoreVisibility`); the colour alone is the
/// month overview the owner asked for.
struct RecoveryMonthCalendar: View {
    /// Daily rows (`repo.days`); only `day` + `recovery` are read.
    let days: [DailyMetric]
    /// The day Today is currently showing; highlighted and used to pick the opening month.
    let selected: Date
    /// The latest pickable day (today's logical day). Later days render disabled.
    let maxDate: Date
    let onPick: (Date) -> Void

    @AppStorage(ScoreVisibility.hiddenKey) private var scoresHidden = true

    var body: some View {
        MonthHeatCalendar(
            values: Self.recoveryByDay(days),
            color: { StrandPalette.recoveryColor($0) },
            cellLabel: scoresHidden ? nil : { String(Int($0.rounded())) },
            summary: { count, mean in
                scoresHidden
                    ? String(localized: "\(count) scored days")
                    : String(localized: "\(count) scored days · average \(Int(mean.rounded()))%")
            },
            emptySummary: String(localized: "No recovery scores this month"),
            selected: selected, maxDate: maxDate, onPick: onPick)
            .padding(16)
            .frame(minWidth: 320)
    }

    /// Day key → recovery, scored days only. A later row for the same key wins (matches the
    /// `days.last(where:)` lookup Today uses).
    static func recoveryByDay(_ days: [DailyMetric]) -> [String: Double] {
        var map: [String: Double] = [:]
        for d in days { if let r = d.recovery { map[d.day] = r } }
        return map
    }
}
