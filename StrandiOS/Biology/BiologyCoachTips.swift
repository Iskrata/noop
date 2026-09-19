import SwiftUI
import StrandDesign
import WhoopStore

/// Fork: Coach tips for one lab report (a test date) — generated once per report and cached
/// (`AICoachEngine.labReportTips`). Lab's report picker chooses `day`.
struct BiologyCoachTips: View {
    @EnvironmentObject var coach: AICoachEngine
    let day: String
    /// Every Lab Book reading shown in Lab (earlier reports give the trend).
    let rows: [LabMarkerRow]

    var body: some View {
        if coach.canSendCoachData {
            CoachTipsCard(title: "Coach on the \(LabBookFormat.dayFromKey(day)) report",
                          id: day + "|" + AICoachEngine.labFingerprint(day: day, rows: rows)) {
                await coach.labReportTips(day: day, rows: rows, sex: AICoachEngine.profileSex) { key in
                    BiologyNames.name(for: key, readings: rows.filter { $0.markerKey == key })
                }
            }
        }
    }
}
