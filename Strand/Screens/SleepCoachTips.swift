import SwiftUI
import StrandDesign

/// Fork: the Sleep screen's Coach tips — actionable advice from the last 7 nights, generated once per wake day
/// (after that night is in) and cached (`AICoachEngine.sleepWeekTips`). Hidden when the Coach can't send data.
struct SleepCoachTips: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var coach: AICoachEngine

    private var wakeDay: String? { AICoachEngine.sleepTipsWakeDay(days: repo.days) }

    var body: some View {
        if let wakeDay, coach.canSendCoachData {
            CoachTipsCard(title: "Sleep better this week", id: wakeDay) {
                await coach.sleepWeekTips(wakeDay: wakeDay)
            }
        }
    }
}
