import Foundation
import WhoopStore

/// Fork: write the day's coaching line and sleep tips as soon as a re-score pass has a closed night, so
/// Today and Sleep open on them instead of waiting on a request. Both go through the same once-only cache
/// the screens read (`CoachReplies.swift`), so this spends nothing once they exist.
extension AICoachEngine {

    /// The night the sleep tips describe: the latest one that is in and closed. A night still being
    /// recorded (`OpenNight`) waits, so the tips are written once, from the whole night.
    static func sleepTipsWakeDay(days: [DailyMetric]) -> String? {
        days.last(where: { $0.totalSleepMin != nil && !OpenNight.isOpen(day: $0.day) })?.day
    }

    /// Called after every pass. Requests only what is missing for today and only once today's night closed.
    func prefetchDailyCoaching() async {
        guard canSendCoachData else { return }
        if let wakeDay = Self.sleepTipsWakeDay(days: repo.days) {
            _ = await sleepWeekTips(wakeDay: wakeDay)
        }
        // Today's line from today's OWN scores, exactly what Today passes (`LiquidTodayView.heroCard`).
        guard let today = repo.today, !OpenNight.isOpen(day: today.day), let charge = today.recovery else { return }
        let rest = await repo.exploreSeries(key: "sleep_performance", source: "my-whoop")
            .last(where: { $0.day == today.day })?.value
        _ = await coachingLine(dayKey: today.day, charge: charge, rest: rest)
    }
}
