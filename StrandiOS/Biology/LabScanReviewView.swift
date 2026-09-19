import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

/// Fork: the review step of the lab-report scan. Every extracted row is editable (marker, value, unit,
/// range, date) or removable; rows that need a second look carry orange flags. Nothing is written until
/// the user taps Save.
struct LabScanReviewView: View {
    @State var rows: [LabScanCandidate]
    let onSave: (_ rows: [LabScanCandidate], _ reportDay: String) async -> Void

    @State private var reportDate = Date()
    @State private var saving = false

    init(rows: [LabScanCandidate], onSave: @escaping (_ rows: [LabScanCandidate], _ reportDay: String) async -> Void) {
        _rows = State(initialValue: rows)
        self.onSave = onSave
    }

    private var reportDay: String { LabBookFormat.dayKey(reportDate) }
    private var flaggedCount: Int { rows.filter { !$0.flags.subtracting([.noDate]).isEmpty }.count }
    private var savable: Bool {
        !rows.isEmpty && rows.allSatisfy { r in
            let p = r.parsedValue
            return p.value != nil || !(p.text ?? "").isEmpty
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                summaryCard
                ForEach($rows) { $row in
                    LabScanRowEditor(row: $row, onRemap: { remap(row.id, to: $0) }, onRemove: { remove(row.id) })
                }
                NoopButton(saving ? "Saving…" : "Save \(rows.count) readings", systemImage: "checkmark",
                           kind: .primary, fullWidth: true) {
                    saving = true
                    Task {
                        await onSave(rows, reportDay)
                        saving = false
                    }
                }
                .disabled(!savable || saving)
                Text("Values are read by AI and can be wrong. Compare each row with your report before saving.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .onAppear {
            if let day = rows.compactMap(\.day).max(), let date = LabScanReviewView.dayFormatter.date(from: day) {
                reportDate = date
            }
        }
    }

    private var summaryCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(rows.count == 1 ? "1 result found" : "\(rows.count) results found")
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                if flaggedCount > 0 {
                    Label(flaggedCount == 1 ? "1 row needs a look" : "\(flaggedCount) rows need a look",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(StrandFont.subhead)
                        .foregroundStyle(HealthMonitorSection.outOfRangeColor)
                }
                DatePicker("Report date", selection: $reportDate, in: ...Date(), displayedComponents: .date)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text("Used for rows where no sample date was read.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func remap(_ id: String, to key: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }),
              let re = LabReportScan.candidate(rows[i].item, id: id, forcedKey: key) else { return }
        rows[i] = re
        LabReportScan.markDuplicates(&rows)
    }

    private func remove(_ id: String) {
        rows.removeAll { $0.id == id }
        LabReportScan.markDuplicates(&rows)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Save mapping

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
}
