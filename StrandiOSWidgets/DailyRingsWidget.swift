import WidgetKit
import SwiftUI
import StrandDesign

/// Fork: Bevel-style small Home Screen widget. The date in the top-left corner and Today's three hero
/// rings on a 2×2 grid: Effort top-right (with its target band hatched), Charge bottom-left, Rest
/// bottom-right. The rings are Today's own `ScoreRingGauge`, so the widget and the hero cannot drift.
///
/// Reads the same App Group snapshot and timeline as `NOOPWidget` (`NOOPProvider`, whose midnight entry
/// turns the date on time); `WidgetSnapshot.dailyScores(on:)` decides which numbers still belong to the
/// entry's day.
struct DailyRingsWidgetView: View {
    let entry: NOOPEntry

    private var snap: WidgetSnapshot { entry.snapshot }
    private var scores: (charge: Int?, effort: Int?, rest: Int?, effortTarget: ClosedRange<Double>?) {
        snap.dailyScores(on: entry.date)
    }

    private static let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = (min(geo.size.width, geo.size.height) - Self.spacing) / 2
            Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
                GridRow {
                    dateBlock.frame(width: side, height: side, alignment: .topLeading)
                    topRight(side)
                }
                GridRow {
                    bottomLeft(side)
                    bottomRight(side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(10)
    }

    // MARK: - Date

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(StrandFont.rounded(15, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            Text(entry.date.formatted(.dateTime.month(.abbreviated)))
                .font(StrandFont.rounded(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
            Text(entry.date.formatted(.dateTime.day()))
                .font(StrandFont.rounded(22, weight: .bold))
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.leading, 6)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rings

    @ViewBuilder
    private func topRight(_ side: CGFloat) -> some View {
        if snap.hideScores == true {
            raw("Heart rate", value: snap.bpm, over: 180, tint: StrandPalette.effortColor, side: side)
        } else {
            let whoop = snap.effortWhoop == true
            let effort = scores.effort.map(Double.init)
            // The published display string carries the exact one-decimal WHOOP value; the Int is rounded.
            let shown = whoop ? effort.map { Double(snap.effortDisplay ?? "") ?? $0 * 21 / 100 } : effort
            ring("Effort", score: shown, max: whoop ? 21 : 100, decimals: whoop ? 1 : 0,
                 tint: StrandPalette.effortColor, target: scores.effortTarget, side: side)
        }
    }

    @ViewBuilder
    private func bottomLeft(_ side: CGFloat) -> some View {
        if snap.hideScores == true {
            raw("Heart rate variability", value: snap.hrv, over: 120, tint: StrandPalette.chargeColor, side: side)
        } else {
            ring("Charge", score: scores.charge.map(Double.init), tint: StrandPalette.chargeColor, side: side)
        }
    }

    @ViewBuilder
    private func bottomRight(_ side: CGFloat) -> some View {
        if snap.hideScores == true {
            raw("Resting heart rate", value: snap.restingHr, over: 100, tint: StrandPalette.restColor, side: side)
        } else {
            ring("Rest", score: scores.rest.map(Double.init), tint: StrandPalette.restColor, side: side)
        }
    }

    /// One score ring, coloured and shaped exactly like Today's `HeroScoreCell`.
    private func ring(_ label: String, score: Double?, max: Double = 100, decimals: Int = 0,
                      tint: Color, target: ClosedRange<Double>? = nil, side: CGFloat) -> some View {
        ScoreRingGauge(score: score, maxValue: max, decimals: decimals,
                       colors: [tint.opacity(0.55), tint], target: target,
                       unit: decimals > 0 ? nil : "%", diameter: side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(score.map {
                decimals > 0 ? String(format: "%.1f", $0) : "\(Int($0.rounded())) percent"
            } ?? "No data"))
    }

    /// Hide-scores substitute (#hide-scores): a raw measurement in the same ring, filled against a
    /// nominal ceiling like `NOOPWidget.rawMetricsRow`, with no unit so it never reads as a percentage.
    private func raw(_ label: String, value: Int?, over ceiling: Double, tint: Color, side: CGFloat) -> some View {
        // The gauge clamps its own fill, so the read-out stays the true value above the ceiling.
        ScoreRingGauge(score: value.map(Double.init),
                       maxValue: ceiling, colors: [tint.opacity(0.55), tint], unit: nil, diameter: side)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value.map(String.init) ?? "No data"))
    }
}

struct DailyRingsWidget: Widget {
    let kind = "DailyRingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NOOPProvider()) { entry in
            DailyRingsWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceRaised, for: .widget)
        }
        .configurationDisplayName("Daily Rings")
        .description("Today's date with Effort, Charge and Rest as rings.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
