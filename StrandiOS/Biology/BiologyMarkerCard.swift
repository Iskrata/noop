import SwiftUI
import StrandDesign
import StrandImport

/// Fork: one Biology marker — name, latest value and unit, where it sits in the report's reference range
/// (green inside, orange outside, as on Today's Health Monitor), the change since last time and a sparkline.
struct BiologyMarkerCard: View {
    let marker: BiologyMarker

    private var tint: Color {
        switch marker.status {
        case .inRange?:         return HealthMonitorSection.inRangeColor
        case .below?, .above?:  return HealthMonitorSection.outOfRangeColor
        case nil:               return StrandPalette.textTertiary
        }
    }

    private var statusText: String {
        switch marker.status {
        case .inRange?: return String(localized: "In range")
        case .below?:   return String(localized: "Below range")
        case .above?:   return String(localized: "Above range")
        case nil:       return marker.latest.map { String(localized: "Tested \(LabBookFormat.dayFromKey($0.day))") } ?? ""
        }
    }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker.name)
                        .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(statusText).font(StrandFont.footnote.weight(.semibold)).foregroundStyle(tint)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(marker.valueLabel).font(StrandFont.rounded(28)).foregroundStyle(StrandPalette.textPrimary)
                    Text(marker.latest?.unit ?? "").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                    Spacer(minLength: 8)
                    if let change = marker.change, change != 0 {
                        Label(LabBookFormat.value(abs(change), key: marker.key),
                              systemImage: change > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
                    }
                    let values = marker.numeric.compactMap(\.value)
                    if values.count > 1 {
                        Sparkline(values: values,
                                  gradient: Gradient(colors: [tint.opacity(0.4), tint]),
                                  showsHover: false)
                            .frame(width: 64, height: 26)
                            .accessibilityHidden(true)
                    }
                }
                if let range = marker.range, let v = marker.latest?.value {
                    BiologyRangeBar(range: range, position: range.position(v), tint: tint)
                        .frame(height: 10)
                    Text("Report range \(marker.latest?.referenceText ?? range.text(decimals: 1)) \(marker.latest?.unit ?? "")")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal track: the report's range as a solid band, the rest dimmed, and a ring at the reading.
struct BiologyRangeBar: View {
    let range: LabReferenceRange
    let position: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.surfaceBase.opacity(0.7))
                Capsule().fill(HealthMonitorSection.inRangeColor.opacity(0.55))
                    .frame(width: w * (range.band.upperBound - range.band.lowerBound), height: h * 0.5)
                    .offset(x: w * range.band.lowerBound)
                Circle().strokeBorder(tint, lineWidth: 2.5)
                    .background(Circle().fill(StrandPalette.surfaceRaised))
                    .frame(width: h + 4, height: h + 4)
                    .offset(x: w * position - (h + 4) / 2)
            }
            .frame(height: h)
        }
        .accessibilityHidden(true)
    }
}
