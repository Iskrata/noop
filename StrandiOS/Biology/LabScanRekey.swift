import Foundation
import StrandImport
import WhoopStore

/// Fork: folds scanned readings saved under a free-name `custom_*` key onto the scan vocabulary's stable key
/// (`LabReportScan.rekey`), so two reports that spelled a test differently ("BASO %" vs "Basophils %
/// (BASO %)") share one history. Idempotent and cheap when nothing needs moving: the new row is written
/// first, then the old one deleted (the store re-projects both day cells).
enum LabScanRekey {

    /// Returns true when any reading moved (the caller reloads).
    static func run(_ rows: [LabMarkerRow], repo: Repository) async -> Bool {
        let moves: [(old: LabMarkerRow, new: LabMarkerRow)] = rows.compactMap { row in
            guard row.source == LabReportScan.sourceId,
                  let key = LabReportScan.rekey(markerKey: row.markerKey,
                                                reportName: LabReportScan.reportName(fromNote: row.note),
                                                unit: row.unit) else { return nil }
            var moved = row
            moved.id = UUID().uuidString
            moved.markerKey = key
            return (row, moved)
        }
        guard !moves.isEmpty, let store = await repo.storeHandle() else { return false }
        do {
            try await store.upsertLabMarkers(moves.map(\.new))
            for m in moves { _ = try await store.deleteLabMarker(id: m.old.id) }
            NSLog("LabScan: re-keyed %d reading(s) onto the scan vocabulary", moves.count)
            return true
        } catch {
            NSLog("LabScan: re-key failed - \(error)")
            return false
        }
    }
}
