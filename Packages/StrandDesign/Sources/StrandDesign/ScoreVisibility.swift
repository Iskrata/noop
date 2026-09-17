import Foundation

/// Whether NOOP's own composite scores (Charge/recovery, Effort/strain, Rest/sleep-score, Stress) are
/// hidden across the app, widgets, Live Activity and score-based notifications — for someone who
/// already scores themselves elsewhere (this fork's use case: NOOP feeds Apple Health, and Bevel does
/// the scoring). Raw measurements (HRV, resting HR, sleep stages, heart rate, skin temp, respiration,
/// SpO2, steps) are UNAFFECTED by this flag and always shown.
///
/// DEFAULT TRUE for this fork — see the Hide-scores toggle in `SettingsView`'s Appearance section.
///
/// One shared accessor rather than scattered `UserDefaults`/`@AppStorage` reads, so every surface
/// (SwiftUI screens, the widget-snapshot publisher, the Live Activity controller, notifiers) agrees on
/// the same flag through the same key. A View that must also re-render live when the toggle flips still
/// needs its own `@AppStorage(ScoreVisibility.hiddenKey)` (SwiftUI's invalidation is tied to the property
/// wrapper observing the view), but both read the identical `UserDefaults.standard` key, so they can
/// never disagree.
public enum ScoreVisibility {
    /// The `@AppStorage` key shared by `SettingsView`'s toggle and every one-shot reader below.
    public static let hiddenKey = "noop.hideScores"

    /// One-shot read for non-View call sites: the widget-snapshot publisher, the Live Activity
    /// controller, and score-based notifiers. Defaults to `true` (this fork's default) when the key has
    /// never been written — `@AppStorage`'s own default only applies inside the declaring View, so a
    /// plain `UserDefaults.standard.bool(forKey:)` on a fresh install would otherwise read `false`.
    public static var hidden: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: hiddenKey) == nil ? true : defaults.bool(forKey: hiddenKey)
    }
}
