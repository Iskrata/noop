import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: SLEEP TIMING — last night's bed/wake against the wearer's USUAL window (the median of the previous 14
/// main nights), on an evening→noon timeline with hour labels. Replaces upstream's 24 h body-clock dial, whose
/// "your clock" came from a cosinor fit of daytime HR: afternoon training pulled its peak to 15:41 and it
/// prescribed 22:25–06:10 to someone who had slept ~00:30–09:00 for weeks. The usual window is always true to
/// the wearer's own data; the timeline reads without decoding a dial.
struct SleepTimingCard: View {
    @EnvironmentObject var repo: Repository
    /// Last night's main sleep (the Sleep screen's resolved night).
    let night: CachedSleepSession

    private var hue: Color { StrandPalette.restLine }

    var body: some View {
        let actual = SleepTiming.window(night)
        if let usual = SleepTiming.usual(nights: repo.sleeps, excluding: night) {
            let axis = SleepTiming.axis([actual, usual])
            NoopCard(tint: hue) {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleep timing").strandOverline()
                        Text("Last night against your usual (last 14 nights)")
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    }
                    timeline(actual: actual, usual: usual, axis: axis)
                        .frame(height: 78)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Last night \(SleepTiming.clock(actual.bed)) to \(SleepTiming.clock(actual.wake)); usual \(SleepTiming.clock(usual.bed)) to \(SleepTiming.clock(usual.wake))"))
                    legend(usual: usual)
                    Text(SleepTiming.caption(actual: actual, usual: usual))
                        .font(StrandFont.title2).foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func timeline(actual: SleepTiming.Window, usual: SleepTiming.Window,
                          axis: ClosedRange<Double>) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> CGFloat = { CGFloat(($0 - axis.lowerBound) / (axis.upperBound - axis.lowerBound)) * w }
            let barY: CGFloat = 38
            ZStack(alignment: .topLeading) {
                // Axis track.
                Capsule().fill(StrandPalette.surfaceInset)
                    .frame(width: w, height: 4).offset(y: barY - 2)
                // Usual window: a faint dashed band.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hue.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(hue.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .frame(width: max(x(usual.wake) - x(usual.bed), 2), height: 28)
                    .offset(x: x(usual.bed), y: barY - 14)
                // Last night: a solid bar with its times above the ends.
                Capsule().fill(hue)
                    .frame(width: max(x(actual.wake) - x(actual.bed), 4), height: 12)
                    .offset(x: x(actual.bed), y: barY - 6)
                timeLabel(SleepTiming.clock(actual.bed), at: x(actual.bed), width: w, y: 0)
                timeLabel(SleepTiming.clock(actual.wake), at: x(actual.wake), width: w, y: 0)
                // Hour labels every 4 h.
                ForEach(SleepTiming.hourTicks(axis), id: \.self) { h in
                    Text(SleepTiming.clock(h, minutes: false))
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize()
                        .position(x: min(max(x(h), 12), w - 12), y: barY + 30)
                }
            }
        }
    }

    private func timeLabel(_ text: String, at x: CGFloat, width: CGFloat, y: CGFloat) -> some View {
        Text(text).font(StrandFont.captionNumber.weight(.semibold)).foregroundStyle(StrandPalette.textPrimary)
            .fixedSize()
            .position(x: min(max(x, 18), width - 18), y: y + 8)
    }

    private func legend(usual: SleepTiming.Window) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Capsule().fill(hue).frame(width: 18, height: 5)
                Text("Last night").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(hue.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(hue.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .frame(width: 18, height: 10)
                Text("Usual \(SleepTiming.clock(usual.bed))–\(SleepTiming.clock(usual.wake))")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
        }
        .accessibilityHidden(true)
    }
}

/// Pure timing maths for `SleepTimingCard` (unit-tested). Times are hours on a NOON-based clock (12:00 → 0,
/// 00:00 → 12, 09:00 → 21), so a night never wraps and medians/spans are plain arithmetic.
enum SleepTiming {
    struct Window: Equatable {
        let bed: Double
        let wake: Double
    }

    static func noonHours(_ ts: Int, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Double(((c.hour ?? 0) + 12) % 24) + Double(c.minute ?? 0) / 60
    }

    static func window(_ s: CachedSleepSession, calendar: Calendar = .current) -> Window {
        let bed = noonHours(s.effectiveStartTs, calendar: calendar)
        let wake = noonHours(s.endTs, calendar: calendar)
        return Window(bed: bed, wake: wake <= bed ? wake + 24 : wake)   // a wake past noon runs on, not back
    }

    /// Median bed and wake of the last 14 main nights (≥ 3 h, the longest per wake day) before `excluding`.
    /// nil with fewer than 3 such nights.
    static func usual(nights: [CachedSleepSession], excluding night: CachedSleepSession,
                      calendar: Calendar = .current) -> Window? {
        var main: [Int: CachedSleepSession] = [:]   // wake day (start of day ts) → longest session
        for s in nights where s.endTs < night.endTs - 3_600 && s.endTs - s.effectiveStartTs >= 3 * 3_600 {
            let day = Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.endTs))).timeIntervalSince1970)
            if let cur = main[day], cur.endTs - cur.effectiveStartTs >= s.endTs - s.effectiveStartTs { continue }
            main[day] = s
        }
        let recent = main.sorted { $0.key < $1.key }.suffix(14).map { window($0.value, calendar: calendar) }
        guard recent.count >= 3 else { return nil }
        return Window(bed: median(recent.map(\.bed)), wake: median(recent.map(\.wake)))
    }

    /// The timeline's span: 20:00 → 12:00 by default, widened (to even hours) to fit every window.
    static func axis(_ windows: [Window]) -> ClosedRange<Double> {
        let lo = min(8, windows.map(\.bed).min() ?? 8)
        let hi = max(24, windows.map(\.wake).max() ?? 24)
        return (floor(lo / 2) * 2)...(ceil(hi / 2) * 2)
    }

    static func hourTicks(_ axis: ClosedRange<Double>) -> [Double] {
        Array(stride(from: axis.lowerBound, through: axis.upperBound, by: 4))
    }

    /// "00:35" for a noon-clock hour; "00" with `minutes: false`.
    static func clock(_ noonHours: Double, minutes: Bool = true) -> String {
        let total = Int((noonHours * 60).rounded())
        let h = ((total / 60) + 12) % 24, m = total % 60
        return minutes ? String(format: "%02d:%02d", h, m) : String(format: "%02d", h)
    }

    /// "Bed 35 min later · woke on time vs usual" — minutes rounded to 5; within 15 min counts as on time.
    static func caption(actual: Window, usual: Window) -> String {
        let bed = Int(((actual.bed - usual.bed) * 60 / 5).rounded()) * 5
        let wake = Int(((actual.wake - usual.wake) * 60 / 5).rounded()) * 5
        if abs(bed) < 15 && abs(wake) < 15 { return String(localized: "Right on your usual schedule") }
        func part(_ minutes: Int, _ onTime: String, _ later: (String) -> String, _ earlier: (String) -> String) -> String {
            if abs(minutes) < 15 { return onTime }
            let amount = abs(minutes) >= 60
                ? (abs(minutes) % 60 == 0 ? "\(abs(minutes) / 60) h" : "\(abs(minutes) / 60) h \(abs(minutes) % 60) min")
                : "\(abs(minutes)) min"
            return minutes > 0 ? later(amount) : earlier(amount)
        }
        let bedText = part(bed, String(localized: "Bed on time"),
                           { String(localized: "Bed \($0) later") }, { String(localized: "Bed \($0) earlier") })
        let wakeText = part(wake, String(localized: "woke on time"),
                            { String(localized: "woke \($0) later") }, { String(localized: "woke \($0) earlier") })
        return "\(bedText) · \(wakeText)"
    }

    private static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
