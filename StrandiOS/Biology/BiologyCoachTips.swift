import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: Coach tips for one lab report (a test date) — generated once per report and cached
/// (`AICoachEngine.labReportTips`). The picker switches between reports; the latest is shown first.
struct BiologyCoachTips: View {
    @EnvironmentObject var coach: AICoachEngine
    /// Every Lab Book reading shown in Biology (earlier reports give the trend).
    let rows: [LabMarkerRow]

    @State private var selectedDay: String?

    private var reportDays: [String] { Array(Set(rows.map(\.day))).sorted(by: >) }
    private var day: String? { selectedDay ?? reportDays.first }

    var body: some View {
        if let day, coach.canSendCoachData {
            VStack(alignment: .leading, spacing: 8) {
                if reportDays.count > 1 {
                    Menu {
                        ForEach(reportDays, id: \.self) { d in
                            Button(LabBookFormat.dayFromKey(d)) { selectedDay = d }
                        }
                    } label: {
                        Label("Report of \(LabBookFormat.dayFromKey(day))", systemImage: "calendar")
                            .font(StrandFont.footnote.weight(.semibold)).foregroundStyle(StrandPalette.accent)
                    }
                }
                CoachTipsCard(title: "Coach on this report", id: day + "|" + AICoachEngine.labFingerprint(day: day, rows: rows)) {
                    await coach.labReportTips(day: day, rows: rows, sex: AICoachEngine.profileSex) { key in
                        BiologyNames.name(for: key, readings: rows.filter { $0.markerKey == key })
                    }
                }
            }
        }
    }
}
