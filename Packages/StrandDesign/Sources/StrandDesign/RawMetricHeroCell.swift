import SwiftUI

/// A hero-row slot that stands in for a hidden composite score (`ScoreVisibility.hidden`), at the same
/// footprint as the `GlowRing`/`LiquidScoreGauge` it replaces so Today's hero row never reflows between
/// the two states. Shows a raw measurement instead of blank space — e.g. HRV + resting HR where the
/// Charge ring used to be, or time asleep where the Rest ring used to be.
///
/// Shared by `TodayView` (macOS + the non-Liquid iOS path) and `LiquidTodayView` so the substitution
/// reads identically wherever it appears, rather than each screen inventing its own.
public struct RawMetricHeroCell: View {
    let symbol: String
    let primary: String?
    let primaryUnit: String?
    let secondary: String?
    let label: String
    let diameter: CGFloat
    let tint: Color

    public init(
        symbol: String,
        primary: String?,
        primaryUnit: String? = nil,
        secondary: String? = nil,
        label: String,
        diameter: CGFloat,
        tint: Color = StrandPalette.textSecondary
    ) {
        self.symbol = symbol
        self.primary = primary
        self.primaryUnit = primaryUnit
        self.secondary = secondary
        self.label = label
        self.diameter = diameter
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(StrandPalette.hairline, lineWidth: max(2, diameter * 0.045))
                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: diameter * 0.16, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(primary ?? "–")
                        .font(StrandFont.rounded(diameter * 0.22, weight: .bold))
                        .foregroundStyle(primary == nil ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let primaryUnit, primary != nil {
                        Text(primaryUnit)
                            .font(.system(size: diameter * 0.10))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.system(size: diameter * 0.10))
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, diameter * 0.08)
            }
            .frame(width: diameter, height: diameter)
            Text(label)
                .font(.caption2)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text([primary.map { "\($0)\(primaryUnit.map { " \($0)" } ?? "")" }, secondary]
            .compactMap { $0 }.joined(separator: ", ").isEmpty ? "No data"
            : [primary.map { "\($0)\(primaryUnit.map { " \($0)" } ?? "")" }, secondary]
                .compactMap { $0 }.joined(separator: ", ")))
    }

    /// Format minutes as "7h 32m" (or "42m" under an hour) — shared so the Rest raw-metric substitute
    /// (time asleep) reads the same on every caller instead of each screen writing its own duration math.
    public static func hoursMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
