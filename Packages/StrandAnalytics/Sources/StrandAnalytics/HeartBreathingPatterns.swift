import Foundation

/// Fork: when the irregular-rhythm and breathing-disturbance screens have seen a REPEATING pattern — the
/// only thing the Today banner speaks up for. A single episode or a single elevated night stays in the Lab
/// tab: both screens are noisy night to night (Hayano 2022 found the CVHR index varies 66% between nights),
/// and a one-off is far more likely to be artifact than a repeat.
///
/// Day keys are local `yyyy-MM-dd`, so string order is date order.
public enum HeartBreathingPatterns {
    /// Irregular rhythm: episodes on at least `rhythmMinDays` distinct days within `rhythmWindowDays`.
    public static let rhythmWindowDays = 14
    public static let rhythmMinDays = 2
    /// Breathing: Apple's Sleep Apnea Notification rule (FDA K240929) — within `breathingWindowDays`, at
    /// least `breathingMinNights` readable nights and at least half of them elevated.
    public static let breathingWindowDays = 30
    public static let breathingMinNights = 10
    public static let breathingMinElevatedShare = 0.5

    public struct RhythmPattern: Equatable, Sendable {
        public let daysWithEpisodes: [String]
        public var repeating: Bool { daysWithEpisodes.count >= rhythmMinDays }
    }

    public struct BreathingPattern: Equatable, Sendable {
        public let readableNights: Int
        public let elevatedNights: Int
        public var repeating: Bool {
            readableNights >= breathingMinNights
                && Double(elevatedNights) >= breathingMinElevatedShare * Double(readableNights)
        }
    }

    /// `episodesByDay` holds the day's episode count; `since` is the oldest day key inside the window.
    public static func rhythm(episodesByDay: [String: Int], since: String) -> RhythmPattern {
        RhythmPattern(daysWithEpisodes: episodesByDay.filter { $0.key >= since && $0.value > 0 }.keys.sorted())
    }

    /// `nights` maps a wake-day key to that night's index and readable hours.
    public static func breathing(nights: [String: (index: Double, hours: Double)], since: String) -> BreathingPattern {
        let readable = nights.filter { $0.key >= since && $0.value.hours >= CvhrDetector.minReadableHours }
        return BreathingPattern(readableNights: readable.count,
                                elevatedNights: readable.filter { $0.value.index >= CvhrDetector.elevatedIndex }.count)
    }
}
