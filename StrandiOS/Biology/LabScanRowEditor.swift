import SwiftUI
import StrandDesign
import StrandImport

/// Fork: one editable row of the lab-scan review — which marker it lands on, the value/unit/range as they
/// will be saved, the flags that need a look, and remove.
struct LabScanRowEditor: View {
    @Binding var row: LabScanCandidate
    let onRemap: (_ key: String) -> Void
    let onRemove: () -> Void

    private var flagged: Bool { !row.flags.subtracting([.noDate]).isEmpty }

    var body: some View {
        NoopCard(tint: flagged ? HealthMonitorSection.outOfRangeColor : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    markerMenu
                    Spacer(minLength: 8)
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 14))
                            .foregroundStyle(StrandPalette.statusCritical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this row")
                }
                Text("On report: \(row.item.name) · \(row.item.value) \(row.item.unit ?? "")")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.flags.isEmpty { flagChips }
                HStack(spacing: 8) {
                    field("Value", text: $row.valueInput)
                    field("Unit", text: $row.unit)
                }
                field("Reference range", text: Binding(get: { row.referenceText ?? "" },
                                                       set: { row.referenceText = $0.isEmpty ? nil : $0 }))
                if let day = row.day {
                    Text("Sample date \(LabBookFormat.dayFromKey(day))")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
            }
        }
    }

    private var markerMenu: some View {
        Menu {
            Button("Keep as “\(row.item.name)”") { onRemap(LabReportScan.ownKey(for: row.item.name)) }
            Divider()
            ForEach(LabReportScan.scannableCatalog, id: \.key) { def in
                Button(def.displayName) { onRemap(def.key) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(BiologyNames.name(for: row.markerKey, reportName: row.item.name))
                    .font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
            }
        }
        .accessibilityLabel("Marker: \(BiologyNames.name(for: row.markerKey, reportName: row.item.name)). Change")
    }

    private var flagChips: some View {
        HStack(spacing: 6) {
            ForEach(LabScanFlag.allCases.filter(row.flags.contains), id: \.self) { flag in
                TrendChip(text: Self.label(flag),
                          color: flag == .noDate ? StrandPalette.textTertiary : HealthMonitorSection.outOfRangeColor)
            }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            TextField(title, text: text)
                .font(StrandFont.bodyNumber)
                .foregroundStyle(StrandPalette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceBase.opacity(0.6)))
        }
    }

    static func label(_ flag: LabScanFlag) -> String {
        switch flag {
        case .lowConfidence:    return String(localized: "Check value")
        case .unmapped:         return String(localized: "New marker")
        case .unitNotConverted: return String(localized: "Unit not converted")
        case .notNumeric:       return String(localized: "Text result")
        case .noDate:           return String(localized: "Report date")
        case .duplicate:        return String(localized: "Duplicate")
        }
    }
}
