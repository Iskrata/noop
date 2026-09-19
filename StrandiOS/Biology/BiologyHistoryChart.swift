import SwiftUI
import Charts
import StrandDesign
import StrandImport

/// Fork: a marker's readings over time with the report's reference range shaded behind them; each point is
/// green inside the range and orange outside it. Shown at the top of the marker's detail sheet.
struct BiologyHistoryChart: View {
    let marker: BiologyMarker

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let inRange: Bool?
    }

    private var points: [Point] {
        marker.numeric.compactMap { row in
            guard let v = row.value, let date = BiologyHistoryChart.dayFormatter.date(from: row.day) else { return nil }
            let range = LabReferenceRange.parse(row.referenceText, sex: AICoachEngine.profileSex)
                ?? (row.unit == marker.latest?.unit ? marker.range : nil)
            return Point(id: row.id, date: date, value: v, inRange: range.map { $0.status(v) == .inRange })
        }
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        if let r = marker.range { values += [r.low, r.high].compactMap { $0 } }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, abs(hi) * 0.05, 0.1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("History", overline: "your results over time")
            NoopCard {
                if points.isEmpty {
                    Text("No numeric results to chart yet.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                } else {
                    chart.frame(height: 200)
                }
            }
        }
    }

    private var chart: some View {
        let domain = yDomain
        return Chart {
            if let r = marker.range, let first = points.first?.date, let last = points.last?.date {
                let span = max(last.timeIntervalSince(first), 86_400 * 14)
                RectangleMark(xStart: .value("From", first.addingTimeInterval(-span * 0.1)),
                              xEnd: .value("To", last.addingTimeInterval(span * 0.1)),
                              yStart: .value("Low", r.low ?? domain.lowerBound),
                              yEnd: .value("High", r.high ?? domain.upperBound))
                    .foregroundStyle(HealthMonitorSection.inRangeColor.opacity(0.14))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(marker.name, p.value))
                    .foregroundStyle(StrandPalette.textTertiary.opacity(0.6))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value(marker.name, p.value))
                    .foregroundStyle(color(p.inRange))
                    .symbolSize(60)
                    .annotation(position: .top, spacing: 4) {
                        Text(LabBookFormat.value(p.value, key: marker.key))
                            .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline)
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityLabel("\(marker.name) history, \(points.count) results")
    }

    private func color(_ inRange: Bool?) -> Color {
        switch inRange {
        case true?:  return HealthMonitorSection.inRangeColor
        case false?: return HealthMonitorSection.outOfRangeColor
        case nil:    return StrandPalette.accent
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
