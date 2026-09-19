import Foundation
import StrandImport
import WhoopStore

/// Display names for Biology: the catalog name, else the name printed on the report (carried in a scanned
/// reading's note), else the humanised key without its `custom_` prefix.
enum BiologyNames {
    static func name(for key: String, reportName: String?) -> String {
        if let def = MarkerCatalog.definition(for: key) { return def.displayName }
        if let reportName, !reportName.isEmpty { return reportName }
        return LabBookView.humanise(key.hasPrefix("custom_") ? String(key.dropFirst("custom_".count)) : key)
    }

    static func name(for key: String, readings: [LabMarkerRow]) -> String {
        name(for: key, reportName: readings.reversed().lazy.compactMap { LabReportScan.reportName(fromNote: $0.note) }.first)
    }
}

/// Fork: one marker as the Biology tab shows it — latest reading, the report's range, trend.
struct BiologyMarker: Identifiable {
    let key: String
    let name: String
    let group: BiologyGroup
    /// Oldest first.
    let readings: [LabMarkerRow]

    var id: String { key }
    var latest: LabMarkerRow? { readings.last }
    var numeric: [LabMarkerRow] { readings.filter { $0.value != nil } }

    /// The latest reading's own range, else the most recent range the user's reports gave for this marker
    /// (only from readings in the same unit, so a stray mg/dL range never judges a mmol/L value).
    var range: LabReferenceRange? {
        guard let latest else { return nil }
        if let own = LabReferenceRange.parse(latest.referenceText) { return own }
        return readings.reversed()
            .filter { $0.unit == latest.unit }
            .lazy.compactMap { LabReferenceRange.parse($0.referenceText) }.first
    }

    var status: LabReferenceRange.Status? {
        guard let v = latest?.value, let range else { return nil }
        return range.status(v)
    }

    /// Latest value minus the one before it (numeric readings only).
    var change: Double? {
        let n = numeric.compactMap(\.value)
        guard n.count >= 2 else { return nil }
        return n[n.count - 1] - n[n.count - 2]
    }

    var valueLabel: String {
        guard let latest else { return "—" }
        if let text = latest.valueText, !text.isEmpty { return text }
        if let v = latest.value { return LabBookFormat.value(v, key: key) }
        return "—"
    }

    /// Group every reading by marker key.
    static func build(_ rows: [LabMarkerRow]) -> [BiologyMarker] {
        Dictionary(grouping: rows, by: \.markerKey).map { key, readings in
            let sorted = readings.sorted { $0.takenAt < $1.takenAt }
            return BiologyMarker(key: key, name: BiologyNames.name(for: key, readings: sorted),
                                 group: BiologyGroup.of(key), readings: sorted)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
