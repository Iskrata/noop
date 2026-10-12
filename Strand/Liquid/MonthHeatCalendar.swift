import SwiftUI
import StrandDesign

/// Fork: a month-at-a-glance grid that tints each day by one daily value, with chevrons through earlier
/// months. Shared by the Today recovery calendar (`RecoveryMonthCalendar`) and the Stress screen's month card
/// (`StressMonthCalendarCard`), which differ only in their values, colours, labels and whether a tap picks a day.
struct MonthHeatCalendar: View {
    /// Day key ("yyyy-MM-dd") → that day's value. Days without a key render neutral.
    let values: [String: Double]
    let color: (Double) -> Color
    /// The small number under the day; nil hides it (e.g. recovery with scores hidden).
    let cellLabel: ((Double) -> String)?
    /// The footer line for a month with data, given its day count and mean.
    let summary: (_ count: Int, _ mean: Double) -> String
    /// The footer line for a month with no data.
    let emptySummary: String
    /// Highlighted with an outline and used to pick the opening month.
    let selected: Date
    /// The latest day; later days render dimmed (and disabled when picking).
    let maxDate: Date
    /// Nil makes the cells display-only.
    var onPick: ((Date) -> Void)? = nil

    @State private var monthStart: Date?

    private var calendar: Calendar { Calendar.current }
    private var shownMonth: Date { monthStart ?? Self.startOfMonth(selected, calendar) }
    private var earliestMonth: Date? {
        values.keys.min().flatMap { Self.dayParser.date(from: $0) }.map { Self.startOfMonth($0, calendar) }
    }

    var body: some View {
        let cells = Self.monthCells(monthStart: shownMonth, calendar: calendar)
        VStack(spacing: 12) {
            header
            weekdayRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date, value: values[Self.dayParser.string(from: date)]) }
                    else { Color.clear.frame(height: 40) }
                }
            }
            footer
        }
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

    private func dayCell(_ date: Date, value: Double?) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: maxDate)
        let fill = value.map(color)
        let label = value.flatMap { v in cellLabel.map { $0(v) } }
        return Button { onPick?(date) } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold, design: .rounded))
                if let label {
                    Text(label)
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
        .disabled(isFuture || onPick == nil)
        .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
        .accessibilityValue(Text(label ?? ""))
    }

    @ViewBuilder private var footer: some View {
        let stats = Self.monthStats(values, monthStart: shownMonth, calendar: calendar)
        Text(stats.count > 0 ? summary(stats.count, stats.mean) : emptySummary)
            .font(StrandFont.caption)
            .foregroundStyle(stats.count > 0 ? StrandPalette.textSecondary : StrandPalette.textTertiary)
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

    /// The month's grid: leading `nil` blanks up to the locale's first weekday, then one date per day.
    static func monthCells(monthStart: Date, calendar: Calendar) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates: [Date?] = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: leading) + dates
    }

    /// Count and mean of the days with a value inside the month that starts at `monthStart`.
    static func monthStats(_ map: [String: Double], monthStart: Date,
                           calendar: Calendar) -> (count: Int, mean: Double) {
        let values = monthCells(monthStart: monthStart, calendar: calendar)
            .compactMap { $0 }.compactMap { map[dayParser.string(from: $0)] }
        guard !values.isEmpty else { return (0, 0) }
        return (values.count, values.reduce(0, +) / Double(values.count))
    }
}
