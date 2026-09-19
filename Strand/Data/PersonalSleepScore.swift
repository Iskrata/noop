import Foundation
import StrandAnalytics
import WhoopStore

/// Fork: one Sleep score everywhere, on the wearer's OWN sleep need and consistency.
///
/// Upstream computes the personal need and consistency in the scoring pass (`IntelligenceEngine`, pass 1)
/// but every stored and displayed Sleep (Rest) score then calls `AnalyticsEngine.Rest.composite(daily:)`
/// with the 8 h / neutral defaults, so a 7 h night against an 8.6 h need scored as if the need were 8 h and
/// irregular nights cost nothing. WHOOP's Sleep Performance (2025) weighs hours vs need, consistency,
/// efficiency and sleep stress. The engine publishes the two personal values here each pass; every Sleep
/// score read goes through `composite(_:)`. Charge's sleep term keeps the defaults, which its fitted
/// constants (`RecoveryScorer.wRHR` et al.) were fitted with.
enum PersonalSleepScore {
    private static let needKey = "fork.sleepNeedHours"
    private static let consistencyKey = "fork.sleepConsistency"

    static func publish(needHours: Double, consistency: Double?, defaults: UserDefaults = .standard) {
        defaults.set(needHours, forKey: needKey)
        if let consistency { defaults.set(consistency, forKey: consistencyKey) }
        else { defaults.removeObject(forKey: consistencyKey) }
    }

    static func composite(_ daily: DailyMetric, defaults: UserDefaults = .standard) -> Double? {
        let need = defaults.object(forKey: needKey) as? Double ?? AnalyticsEngine.Rest.defaultNeedHours
        let consistency = defaults.object(forKey: consistencyKey) as? Double
        return AnalyticsEngine.Rest.composite(daily: daily, needHours: need, consistency: consistency)
    }
}
