import Foundation
import StrandImport
import WhoopStore

/// Display names for Biology: the catalog name, else the name printed on the report (carried in a scanned
/// reading's note), else the humanised key without its `custom_` prefix.
enum BiologyNames {
    static func name(for key: String, reportName: String?) -> String {
        if let def = MarkerCatalog.definition(for: key) { return def.displayName }
        if let analyte = LabScanVocabulary.analyte(for: key) { return analyte.displayName }
        if let reportName, !reportName.isEmpty { return reportName }
        return LabBookView.humanise(key.hasPrefix("custom_") ? String(key.dropFirst("custom_".count)) : key)
    }

    static func name(for key: String, readings: [LabMarkerRow]) -> String {
        name(for: key, reportName: readings.reversed().lazy.compactMap { LabReportScan.reportName(fromNote: $0.note) }.first)
    }
}

/// Fork: one marker as the Biology tab shows it — latest reading, the report's range, trend. Everything the
/// cards read is computed ONCE in `init` (at load), never per body pass: a populated screen re-evaluates
/// every card on scroll, and recomputing ranges/filters there made it lag.
struct BiologyMarker: Identifiable {
    let key: String
    let name: String
    let group: BiologyGroup
    /// Oldest first.
    let readings: [LabMarkerRow]
    let latest: LabMarkerRow?
    let numeric: [LabMarkerRow]
    let numericValues: [Double]
    /// The latest reading's own range, else the most recent range the user's reports gave for this marker
    /// (only from readings in the same unit, so a stray mg/dL range never judges a mmol/L value).
    let range: LabReferenceRange?
    let status: LabReferenceRange.Status?
    /// Latest value minus the one before it (numeric readings only).
    let change: Double?
    let valueLabel: String

    var id: String { key }

    init(key: String, name: String, group: BiologyGroup, readings: [LabMarkerRow], sex: String) {
        self.key = key
        self.name = name
        self.group = group
        self.readings = readings
        let latest = readings.last
        self.latest = latest
        numeric = readings.filter { $0.value != nil }
        numericValues = numeric.compactMap(\.value)
        let range: LabReferenceRange? = latest.flatMap { latest in
            LabReferenceRange.parse(latest.referenceText, sex: sex) ?? readings.reversed()
                .filter { $0.unit == latest.unit }
                .lazy.compactMap { LabReferenceRange.parse($0.referenceText, sex: sex) }.first
        }
        self.range = range
        status = latest?.value.flatMap { v in range?.status(v) }
        change = numericValues.count >= 2 ? numericValues[numericValues.count - 1] - numericValues[numericValues.count - 2] : nil
        if let text = latest?.valueText, !text.isEmpty {
            valueLabel = text
        } else if let v = latest?.value {
            valueLabel = LabBookFormat.value(v, key: key)
        } else {
            valueLabel = "—"
        }
    }

    /// Group every reading by marker key.
    static func build(_ rows: [LabMarkerRow], sex: String) -> [BiologyMarker] {
        Dictionary(grouping: rows, by: \.markerKey).map { key, readings in
            let sorted = readings.sorted { $0.takenAt < $1.takenAt }
            return BiologyMarker(key: key, name: BiologyNames.name(for: key, readings: sorted),
                                 group: BiologyGroup.of(key), readings: sorted, sex: sex)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Scan → Lab Book rows

extension LabScanCandidate {
    /// The Lab Book row this candidate saves as. `reportDay` fills a missing sample date. The printed name
    /// rides in the note when it differs from the marker's own name (custom markers display it).
    func labMarkerRow(deviceId: String, reportDay: String) -> LabMarkerRow {
        let day = self.day ?? reportDay
        let parsed = parsedValue
        let catalogName = MarkerCatalog.definition(for: markerKey)?.displayName
        let printed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = printed.caseInsensitiveCompare(catalogName ?? "") == .orderedSame
            ? nil : LabReportScan.reportNamePrefix + printed
        let reference = referenceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LabMarkerRow(id: UUID().uuidString, deviceId: deviceId, markerKey: markerKey,
                            category: category.rawValue, day: day, takenAt: LabBookFormat.noonEpoch(day),
                            value: parsed.value, valueText: parsed.text,
                            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
                            source: LabReportScan.sourceId, note: note,
                            referenceText: reference?.isEmpty == false ? reference : nil)
    }

    /// The day for rows with no printed date: the most common sample date in this scan, else today.
    static func reportDay(_ rows: [LabScanCandidate]) -> String {
        let counts = Dictionary(grouping: rows.compactMap(\.day), by: { $0 }).mapValues(\.count)
        return counts.max { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }?.key
            ?? LabBookFormat.dayKey(Date())
    }

    /// "LDL cholesterol 3.1 mmol/dL — unit not converted" for the saved-summary list.
    var flagSummary: String {
        let reasons: [String] = flags.subtracting([.noDate, .unmapped]).sorted { $0.rawValue < $1.rawValue }.map {
            switch $0 {
            case .lowConfidence:    return String(localized: "hard to read")
            case .unitNotConverted: return String(localized: "unit not converted")
            case .notNumeric:       return String(localized: "text result")
            case .duplicate:        return String(localized: "listed twice")
            case .noDate, .unmapped: return ""
            }
        }
        return "\(item.name) \(valueInput) \(unit) — \(reasons.joined(separator: ", "))"
    }
}
