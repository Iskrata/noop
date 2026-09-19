import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: Bevel's "Health Monitor" grid in place of Key Metrics — six vitals, each with its value, whether it
/// runs lower or higher than the wearer's last 30 nights, and a vertical range bar: blue while inside the
/// personal range (mean ± 1 SD), orange outside it (`HealthMonitorReading`).
struct HealthMonitorSection: View {
    let days: [DailyMetric]
    let dayKey: String
    let cardOpacity: Double
    var fahrenheit: Bool = false

    static let inRangeColor = Color(hex: "#6E8EF7")
    static let outOfRangeColor = Color(hex: "#F28C38")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Monitor").font(StrandFont.rounded(22)).foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 2).padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(HealthMonitorMetric.allCases) { metric in
                    let reading = HealthMonitorReading.resolve(metric, days: days, dayKey: dayKey)
                    if let route = route(metric) {
                        NavigationLink(value: route) { tile(metric, reading) }.buttonStyle(LiquidPressStyle())
                    } else {
                        tile(metric, reading)
                    }
                }
            }
        }
    }

    private func route(_ m: HealthMonitorMetric) -> TabRoute? {
        switch m {
        case .respiratory: return .metric("resp_rate")
        case .restingHr:   return .metric("rhr")
        case .hrv:         return .metric("hrv")
        case .spo2:        return nil
        case .skinTemp:    return .metric("skin_temp")
        case .sleep:       return .sleep
        }
    }

    private func tile(_ m: HealthMonitorMetric, _ r: HealthMonitorReading?) -> some View {
        let tint = (r?.hasRange ?? false) && !(r?.inRange ?? true) ? Self.outOfRangeColor : Self.inRangeColor
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon(m)).font(.system(size: 14, weight: .semibold))
                    Text(title(m)).font(StrandFont.number(16))
                }
                .foregroundStyle(StrandPalette.textTertiary)
                if let r {
                    valueText(m, r.value)
                    if r.hasRange {
                        HStack(spacing: 6) {
                            Image(systemName: r.direction == .lower ? "arrow.down.circle.fill"
                                  : r.direction == .higher ? "arrow.up.circle.fill" : "equal.circle.fill")
                            Text(directionText(r.direction)).font(StrandFont.number(17))
                        }
                        .foregroundStyle(tint)
                    }
                } else {
                    Text("No\ndata").font(StrandFont.rounded(28)).foregroundStyle(StrandPalette.textTertiary.opacity(0.6))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            RangeBar(position: r?.hasRange == true ? r?.position : nil, tint: tint)
                .frame(width: 26, height: 88)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 22, surfaceOpacity: cardOpacity))
    }

    @ViewBuilder
    private func valueText(_ m: HealthMonitorMetric, _ v: Double) -> some View {
        let parts = format(m, v)
        (Text(parts.value).font(StrandFont.rounded(28)).foregroundColor(StrandPalette.textPrimary)
         + Text(parts.unit.isEmpty ? "" : " \(parts.unit)").font(StrandFont.rounded(15))
            .foregroundColor(StrandPalette.textTertiary))
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func format(_ m: HealthMonitorMetric, _ v: Double) -> (value: String, unit: String) {
        switch m {
        case .respiratory: return (String(format: "%.1f", v), "rpm")
        case .restingHr:   return (String(format: "%.1f", v), "bpm")
        case .hrv:         return (String(format: "%.1f", v), "ms")
        case .spo2:        return (String(format: "%.0f", v), "%")
        case .skinTemp:
            let d = fahrenheit ? v * 9 / 5 : v
            return (String(format: "%+.1f", d), fahrenheit ? "Δ°F" : "Δ°C")
        case .sleep:
            let mins = Int(v.rounded())
            return ("\(mins / 60)h \(mins % 60)m", "")
        }
    }

    private func title(_ m: HealthMonitorMetric) -> String {
        switch m {
        case .respiratory: return "RR"
        case .restingHr:   return "RHR"
        case .hrv:         return "HRV"
        case .spo2:        return "SpO2"
        case .skinTemp:    return String(localized: "Temp")
        case .sleep:       return String(localized: "Sleep")
        }
    }

    private func icon(_ m: HealthMonitorMetric) -> String {
        switch m {
        case .respiratory: return "lungs.fill"
        case .restingHr:   return "heart.fill"
        case .hrv:         return "waveform.path.ecg"
        case .spo2:        return "drop.fill"
        case .skinTemp:    return "thermometer.medium"
        case .sleep:       return "bed.double.fill"
        }
    }

    private func directionText(_ d: HealthMonitorReading.Direction) -> String {
        switch d {
        case .lower:   return String(localized: "Lower")
        case .higher:  return String(localized: "Higher")
        case .typical: return String(localized: "Typical")
        }
    }
}

/// The recessed vertical range bar: dashes above and below the personal range, a solid band inside it,
/// and a ring marker at the reading. `position` nil draws the empty track (no data or no range yet).
private struct RangeBar: View {
    let position: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 5
            let h = geo.size.height - inset * 2
            let w = geo.size.width - inset * 2
            let y: (Double) -> CGFloat = { inset + h * CGFloat(1 - $0) }
            ZStack(alignment: .top) {
                Capsule().fill(StrandPalette.surfaceBase.opacity(0.7))
                if let position {
                    // Out-of-range stretches as short dashes.
                    ForEach(Array(dashes(h: h).enumerated()), id: \.offset) { _, f in
                        Capsule().fill(tint.opacity(0.55)).frame(width: w * 0.55, height: 3)
                            .position(x: geo.size.width / 2, y: y(f))
                    }
                    // The in-range band.
                    Capsule().fill(tint)
                        .frame(width: w * 0.55, height: h * CGFloat(HealthMonitorReading.bandHigh - HealthMonitorReading.bandLow))
                        .position(x: geo.size.width / 2,
                                  y: y((HealthMonitorReading.bandLow + HealthMonitorReading.bandHigh) / 2))
                    Circle().strokeBorder(tint, lineWidth: 2.5)
                        .background(Circle().fill(StrandPalette.surfaceRaised))
                        .frame(width: w * 0.8, height: w * 0.8)
                        .position(x: geo.size.width / 2, y: y(position))
                }
            }
        }
    }

    /// Dash centres (0…1) in the two out-of-range stretches.
    private func dashes(h: CGFloat) -> [Double] {
        let step = Double(7 / max(h, 1))
        var out: [Double] = []
        var f = 0.04
        while f < HealthMonitorReading.bandLow - step / 2 { out.append(f); f += step }
        f = HealthMonitorReading.bandHigh + step
        while f < 0.97 { out.append(f); f += step }
        return out
    }
}
