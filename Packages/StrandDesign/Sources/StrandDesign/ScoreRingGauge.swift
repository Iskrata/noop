import SwiftUI

/// Fork: Bevel's hero ring. A recessed dial, a round-capped progress arc from 12 o'clock, the score with a
/// small unit in the centre, and — for Effort — the recommended target band drawn as a hatched arc so the
/// gap between the day so far and the target reads at a glance. Static: no per-frame animation, so it is
/// also the ring the Home Screen "Daily Rings" widget draws (WidgetKit does not run view animations).
public struct ScoreRingGauge: View {
    let score: Double?
    /// The scale `score` is on (100, or 21 for the WHOOP Effort scale).
    var maxValue: Double = 100
    var decimals: Int = 0
    /// Arc colours from the start of the arc to its head.
    let colors: [Color]
    /// Target band as fractions of the dial (0…1), drawn hatched behind the arc.
    var target: ClosedRange<Double>? = nil
    /// Small unit after the number ("%"), nil for none.
    var unit: String? = "%"
    var diameter: CGFloat = 96
    /// Decimal separator for a one-decimal score. The app passes its language-aware locale; the widget
    /// extension (which does not carry the app's language settings) the device's.
    var locale: Locale = .current

    public init(score: Double?, maxValue: Double = 100, decimals: Int = 0, colors: [Color],
                target: ClosedRange<Double>? = nil, unit: String? = "%", diameter: CGFloat = 96,
                locale: Locale = .current) {
        self.score = score
        self.maxValue = maxValue
        self.decimals = decimals
        self.colors = colors
        self.target = target
        self.unit = unit
        self.diameter = diameter
        self.locale = locale
    }

    private var frac: Double { score.map { max(0, min(1, $0 / maxValue)) } ?? 0 }
    private var lineWidth: CGFloat { diameter * 0.12 }

    public var body: some View {
        ZStack {
            // Recessed bezel + track.
            Circle().fill(StrandPalette.surfaceBase.opacity(0.55))
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
                .padding(lineWidth / 2 + diameter * 0.05)
            if let target {
                ring(from: target.lowerBound, to: target.upperBound)
                    .stroke(colors.last ?? .white,
                            style: StrokeStyle(lineWidth: lineWidth * 0.9, lineCap: .butt, dash: [1.5, 2.5]))
                    .opacity(0.75)
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2 + diameter * 0.05)
            }
            if frac > 0 {
                ring(from: 0, to: frac)
                    .stroke(AngularGradient(colors: colors, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(frac, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2 + diameter * 0.05)
            }
            centre
        }
        .frame(width: diameter, height: diameter)
    }

    /// An arc from `a` to `b` (fractions of a turn) from 3 o'clock; callers rotate the stroked arc −90° so
    /// it starts at 12 o'clock with its gradient turning with it.
    private func ring(from a: Double, to b: Double) -> some Shape {
        Circle().trim(from: a, to: b)
    }

    private var centre: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            if let score {
                Text(decimals > 0
                     ? String(format: "%.\(decimals)f", locale: locale, score)
                     : String(Int(score.rounded())))
                    .font(StrandFont.rounded(diameter * 0.27))
                if let unit {
                    Text(unit).font(StrandFont.rounded(diameter * 0.15))
                }
            } else {
                Text("–").font(StrandFont.rounded(diameter * 0.27))
            }
        }
        .foregroundStyle(StrandPalette.textPrimary)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, lineWidth + diameter * 0.06)
    }
}
