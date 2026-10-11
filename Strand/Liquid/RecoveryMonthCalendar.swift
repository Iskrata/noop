import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: the Today day picker as a month-at-a-glance recovery map. Each day cell is filled with
/// `StrandPalette.recoveryColor` of that day's stored recovery (the same tint the Today Charge ring uses),
/// days with no score stay neutral, and chevrons step through previous months. Tapping a day still jumps
/// Today to it, so this replaces the plain graphical `DatePicker` without losing that job.
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
    @State private var monthStart: Date?

    private var calendar: Calendar { Calendar.current }
    private var shownMonth: Date { monthStart ?? Self.startOfMonth(selected, calendar) }
    private var recoveryByDay: [String: Double] { Self.recoveryByDay(days) }
    private var earliestMonth: Date? {
        days.lazy.filter { $0.recovery != nil }.map(\.day).min()
            .flatMap { Self.dayParser.date(from: $0) }
            .map { Self.startOfMonth($0, calendar) }
    }

    var body: some View {
        let map = recoveryByDay
        let cells = Self.monthCells(monthStart: shownMonth, calendar: calendar)
        VStack(spacing: 12) {
            header
            weekdayRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date, recovery: map[Self.dayParser.string(from: date)]) }
                    else { Color.clear.frame(height: 40) }
                }
            }
            summary(map)
        }
        .padding(16)
        .frame(minWidth: 320)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            monthButton("chevron.left", delta: -1, enabled: canStep(-1))
            Spacer()
            Text(shownMonth.formatted(.dateTime.month(.wide).year().locale(AppLanguage.activeLocale)))
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            monthButton("chevron.right", delta: 1, enabled: canStep(1))
        }
    }

    private func monthButton(_ icon: String, delta: Int, enabled: Bool) -> some View {
        Button {
            monthStart = calendar.date(byAdding: .month, value: delta, to: shownMonth)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? StrandPalette.textPrimary : StrandPalette.textTertiary)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? Text("Previous month") : Text("Next month"))
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date, recovery: Double?) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: maxDate)
        let fill = recovery.map { StrandPalette.recoveryColor($0) }
        return Button { onPick(date) } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
                if let recovery, !scoresHidden {
                    Text("\(Int(recovery.rounded()))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .opacity(0.85)
                }
            }
            .foregroundStyle(fill != nil ? Color.black : StrandPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill ?? StrandPalette.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(StrandPalette.textPrimary, lineWidth: isSelected ? 2 : 0)
            )
            .opacity(isFuture ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
        .accessibilityValue(Text(recovery.map { scoresHidden ? "" : "\(Int($0.rounded()))%" } ?? ""))
    }

    @ViewBuilder private func summary(_ map: [String: Double]) -> some View {
        let stats = Self.monthStats(map, monthStart: shownMonth, calendar: calendar)
        if stats.count > 0 {
            Text(scoresHidden
                 ? String(localized: "\(stats.count) scored days")
                 : String(localized: "\(stats.count) scored days · average \(Int(stats.mean.rounded()))%"))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        } else {
            Text("No recovery scores this month")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private func canStep(_ delta: Int) -> Bool {
        if delta > 0 { return shownMonth < Self.startOfMonth(maxDate, calendar) }
        guard let earliest = earliestMonth else { return false }
        return shownMonth > earliest
    }

    // MARK: Pure helpers (unit-tested in RecoveryMonthCalendarTests)

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func startOfMonth(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Day key → recovery, scored days only. A later row for the same key wins (matches the
    /// `days.last(where:)` lookup Today uses).
    static func recoveryByDay(_ days: [DailyMetric]) -> [String: Double] {
        var map: [String: Double] = [:]
        for d in days { if let r = d.recovery { map[d.day] = r } }
        return map
    }

    /// The month's grid: leading `nil` blanks up to the locale's first weekday, then one date per day.
    static func monthCells(monthStart: Date, calendar: Calendar) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: leading) + dates
    }

    /// Count and mean of the scored days inside the month that starts at `monthStart`.
    static func monthStats(_ map: [String: Double], monthStart: Date,
                           calendar: Calendar) -> (count: Int, mean: Double) {
        let values = monthCells(monthStart: monthStart, calendar: calendar)
            .compactMap { $0 }.compactMap { map[dayParser.string(from: $0)] }
        guard !values.isEmpty else { return (0, 0) }
        return (values.count, values.reduce(0, +) / Double(values.count))
    }
}
