import Foundation
import StrandAnalytics
import WhoopStore

/// Fork: one Sleep score everywhere, fitted to WHOOP's 2025 Sleep Performance.
///
/// Upstream stores and shows `AnalyticsEngine.Rest.composite(daily:)` with an 8 h need and neutral
/// consistency. WHOOP's Sleep Performance (since May 2025) weighs hours vs need, sleep consistency, sleep
/// efficiency and sleep stress. Regressing this wearer's own export (sleeps.csv, 376 nights 2025-05 →
/// 2026-08, scratch `sleepfit.py`) on the first three gives R² 0.80, MAE 2.2:
///     performance ≈ −24.9 + 0.375·sufficiency + 0.37·consistency + 0.525·efficiency   (all in %)
/// where sufficiency = min(asleep / need, 1). Sleep stress isn't in the export and isn't modelled.
/// WHOOP's consistency is reproduced from bed/wake timing (`consistency(onsets:wakes:)`, scratch
/// `consfit.py`, r −0.78, MAE 4); end to end the model lands MAE 2.9 against WHOOP's own scores.
///
/// The engine publishes the personal need and the per-wake-day consistency each pass; every Sleep score
/// read goes through `composite(_:)`. Charge's sleep term keeps upstream's composite, which its fitted
/// constants (`RecoveryScorer.wRHR` et al.) were fitted with.
enum PersonalSleepScore {
    private static let needKey = "fork.sleepNeedHours"
    private static let consistencyByDayKey = "fork.sleepConsistencyByDay"

    // MARK: Model (pure)

    /// WHOOP-style consistency (%) for the LAST night of `onsets`/`wakes` (minutes on a continuous clock,
    /// oldest first, up to 4 nights): 93.8 − 0.29 × the mean absolute gap between tonight's bedtime and wake
    /// and the previous nights'. nil with fewer than 2 nights.
    static func consistency(onsets: [Double], wakes: [Double]) -> Double? {
        let on = onsets.suffix(4), wk = wakes.suffix(4)
        guard on.count >= 2, on.count == wk.count, let lastOn = on.last, let lastWk = wk.last else { return nil }
        let gaps = on.dropLast().map { abs(lastOn - $0) } + wk.dropLast().map { abs(lastWk - $0) }
        let mad = gaps.reduce(0, +) / Double(gaps.count)
        return min(100, max(0, 93.79 - 0.2915 * mad))
    }

    /// WHOOP-fitted Sleep Performance (%) from minutes asleep, need (minutes), efficiency (%) and
    /// consistency (%). With no consistency yet, the wearer's typical WHOOP consistency (78 %) stands in.
    static func performance(asleepMin: Double, needMin: Double, efficiencyPct: Double,
                            consistencyPct: Double?) -> Double {
        let sufficiency = needMin > 0 ? min(asleepMin / needMin, 1) * 100 : 100
        let raw = -24.903 + 0.375 * sufficiency + 0.37 * (consistencyPct ?? 78) + 0.525 * efficiencyPct
        return min(100, max(0, raw))
    }

    // MARK: Published inputs

    static func publish(needHours: Double, consistencyByDay: [String: Double],
                        defaults: UserDefaults = .standard) {
        defaults.set(needHours, forKey: needKey)
        var merged = defaults.dictionary(forKey: consistencyByDayKey) as? [String: Double] ?? [:]
        merged.merge(consistencyByDay) { _, new in new }
        defaults.set(merged, forKey: consistencyByDayKey)
    }

    /// The personal sleep need (hours) the engine last published.
    static func needHours(defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: needKey) as? Double ?? AnalyticsEngine.Rest.defaultNeedHours
    }

    /// The published consistency (%) for a wake day, if any.
    static func consistency(day: String, defaults: UserDefaults = .standard) -> Double? {
        (defaults.dictionary(forKey: consistencyByDayKey) as? [String: Double])?[day]
    }

    static func composite(_ daily: DailyMetric, defaults: UserDefaults = .standard) -> Double? {
        guard let asleep = daily.totalSleepMin, asleep > 0, let eff = daily.efficiency else { return nil }
        let need = (defaults.object(forKey: needKey) as? Double ?? AnalyticsEngine.Rest.defaultNeedHours) * 60
        let consistency = (defaults.dictionary(forKey: consistencyByDayKey) as? [String: Double])?[daily.day]
        return performance(asleepMin: asleep, needMin: need, efficiencyPct: eff <= 1 ? eff * 100 : eff,
                           consistencyPct: consistency)
    }
}
