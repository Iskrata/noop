import Foundation

// MARK: - Reference range from the user's own report (fork: Biology tab)
//
// The Lab Book stores a reference range only as the text the user (or the scan) copied from THEIR OWN
// report (`labMarker.referenceText`); NOOP still ships no range tables. This type reads that text back into
// numeric bounds so the Biology tab can draw the report's range bar and say whether the latest reading sits
// inside it. Text it can't read ("see comment", "negative") yields nil and the card shows no bar.
//
// Pure and deterministic — no DB, no I/O.

public struct LabReferenceRange: Equatable, Sendable {
    public let low: Double?
    public let high: Double?

    /// nil when neither bound is present or the bounds are inverted.
    public init?(low: Double?, high: Double?) {
        guard low != nil || high != nil else { return nil }
        if let low, let high, low > high { return nil }
        self.low = low
        self.high = high
    }

    public enum Status: String, Sendable { case below, inRange, above }

    /// Where `value` sits against the range (inclusive bounds).
    public func status(_ value: Double) -> Status {
        if let low, value < low { return .below }
        if let high, value > high { return .above }
        return .inRange
    }

    // MARK: Bar geometry (0…1 along a horizontal track)

    /// The in-range band on the track: two-sided ranges sit in the middle half, "< high" runs from the left
    /// edge, "> low" runs to the right edge.
    public var band: ClosedRange<Double> {
        switch (low, high) {
        case (.some, .some): return 0.25...0.75
        case (nil, .some):   return 0...0.75
        default:             return 0.25...1
        }
    }

    /// The marker position for `value` on the track, clamped inside the ends so the dot stays visible.
    public func position(_ value: Double) -> Double {
        let raw: Double
        switch (low, high) {
        case let (low?, high?):
            let span = high - low
            raw = span > 0 ? 0.25 + 0.5 * (value - low) / span : (value < low ? 0.1 : value > high ? 0.9 : 0.5)
        case let (nil, high?):
            raw = high > 0 ? 0.75 * value / high : (value > high ? 0.9 : 0.5)
        case let (low?, nil):
            raw = low > 0 ? 0.25 * value / low : (value < low ? 0.1 : 0.5)
        default:
            raw = 0.5
        }
        return min(0.97, max(0.03, raw))
    }

    // MARK: Text

    /// "3.00–5.00", "< 5.0", "> 1.2" with `decimals` places — what the scan stores as `referenceText`.
    public func text(decimals: Int) -> String {
        let f: (Double) -> String = { decimals <= 0 ? String(Int($0.rounded())) : String(format: "%.\(decimals)f", $0) }
        switch (low, high) {
        case let (low?, high?): return "\(f(low))–\(f(high))"
        case let (nil, high?):  return "< \(f(high))"
        case let (low?, nil):   return "> \(f(low))"
        default:                return ""
        }
    }

    /// Read a printed range: "3.0 - 5.0", "3,0–5,0", "3 to 5", "< 5.2", "≤5", "up to 5", "> 1.0", "≥ 60",
    /// optionally followed by a unit. nil for anything else.
    public static func parse(_ text: String?) -> LabReferenceRange? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty else { return nil }
        if let m = captures(t, twoSided) {
            return LabReferenceRange(low: number(m[0]), high: number(m[1]))
        }
        if let m = captures(t, upperOnly) {
            return LabReferenceRange(low: nil, high: number(m[0]))
        }
        if let m = captures(t, lowerOnly) {
            return LabReferenceRange(low: number(m[0]), high: nil)
        }
        return nil
    }

    /// `parse`, falling back to the half of a sex-specific range ("жени>1.68 мъже>1.45", "M: 13-17 F: 12-15")
    /// that matches `sex` ("male"/"female").
    public static func parse(_ text: String?, sex: String?) -> LabReferenceRange? {
        if let plain = parse(text) { return plain }
        guard let t = text?.lowercased(), let sex else { return nil }
        let regex = sex.lowercased().hasPrefix("f") ? femaleLabel : maleLabel
        guard let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t) else { return nil }
        return parse(String(t[r]))
    }

    // Compiled once: `parse` runs for every marker card, so building these per call made scrolling lag.
    private static let num = "([0-9]+(?:[.,][0-9]+)?)"
    private static let twoSided = regex("^\(num)\\s*(?:-|–|—|to|\\.\\.)\\s*\(num)(?![0-9])")
    private static let upperOnly = regex("^(?:<=?|≤|up to|under|below)\\s*\(num)(?![0-9])")
    private static let lowerOnly = regex("^(?:>=?|≥|over|above)\\s*\(num)(?![0-9])")

    private static let maleLabel = regex("(?<![\\p{L}])(?:мъже|мъж|men|male|m)\\s*[:=]?\\s*(.+)")
    private static let femaleLabel = regex("(?<![\\p{L}])(?:жени|жена|women|female|f|w)\\s*[:=]?\\s*(.+)")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    private static func captures(_ s: String, _ regex: NSRegularExpression) -> [String]? {
        guard let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: s).map { String(s[$0]) } }
    }
}
