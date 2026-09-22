import SwiftUI
import StrandDesign

/// Fork: the Sleep screen's Coach tips — actionable advice from the last 7 nights, generated once per wake day
/// (after that night is in) and cached (`AICoachEngine.sleepWeekTips`). Hidden when the Coach can't send data.
struct SleepCoachTips: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var coach: AICoachEngine

    /// The latest night that is in and closed: one still being recorded (`OpenNight`) waits, so the tips
    /// are written once, from the whole night.
    private var wakeDay: String? {
        repo.days.last(where: { $0.totalSleepMin != nil && !OpenNight.isOpen(day: $0.day) })?.day
    }

    var body: some View {
        if let wakeDay, coach.canSendCoachData {
            CoachTipsCard(title: "Sleep better this week", id: wakeDay) {
                await coach.sleepWeekTips(wakeDay: wakeDay)
            }
        }
    }
}
