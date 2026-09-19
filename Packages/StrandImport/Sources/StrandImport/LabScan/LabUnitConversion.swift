import Foundation

// MARK: - Lab unit conversion (fork: AI lab-report scan)
//
// A scanned report prints each marker in whatever unit the lab uses (mg/dL in the US, mmol/L in Europe).
// The Lab Book keeps one unit per catalog marker (`MarkerDefinition.canonicalUnit`), so a scanned value is
// converted to that unit before it lands next to earlier readings — otherwise one history would mix
// 130 (mg/dL) and 3.4 (mmol/L) on the same chart. Only well-known, fixed-factor conversions are listed;
// an unknown unit returns nil and the review screen flags the row instead of guessing.
//
// Pure and deterministic — no DB, no I/O.

public enum LabUnitConversion {

    /// Fold a printed unit onto one spelling: lowercase, micro sign / Greek mu / "mc" → "u", no spaces,
    /// superscript two → "2", decimal comma → dot, "litre"/"liter" → "l".
    public static func normalize(_ unit: String) -> String {
        var u = unit.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        u = u.replacingOccurrences(of: "\u{00B5}", with: "u")   // µ micro sign
            .replacingOccurrences(of: "\u{03BC}", with: "u")    // μ Greek mu
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "litre", with: "l")
            .replacingOccurrences(of: "liter", with: "l")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        if u.hasPrefix("mcg") { u = "ug" + u.dropFirst(3) }
        if u.hasPrefix("mcmol") { u = "umol" + u.dropFirst(5) }
        return u
    }

    /// Units that mean the same quantity as a canonical unit (factor 1), keyed by the normalized canonical.
    private static let synonyms: [String: Set<String>] = [
        "mmol/l": ["meq/l"],
        "ug/l": ["ng/ml"],
        "ng/l": ["pg/ml"],
        "miu/l": ["uiu/ml", "mu/l", "uu/ml"],
        "u/l": ["iu/l", "ui/l", "e/l"],
        "ml/min/1.73m2": ["ml/min/1.73", "ml/min", "ml/min/1.73m"],
        "bpm": ["/min", "beats/min", "1/min"],
        "kg": ["kgs"],
    ]

    /// Marker-specific conversions from a normalized unit to the marker's canonical unit.
    private static let factors: [String: [String: (Double) -> Double]] = {
        let cholesterol: [String: (Double) -> Double] = ["mg/dl": { $0 / 38.67 }]
        return [
            "total_cholesterol": cholesterol,
            "ldl": cholesterol,
            "hdl": cholesterol,
            "triglycerides": ["mg/dl": { $0 / 88.57 }],
            "fasting_glucose": ["mg/dl": { $0 / 18.016 }],
            // IFCC mmol/mol from NGSP % (the master equation).
            "hba1c": ["%": { ($0 - 2.15) * 10.929 }],
            "iron": ["ug/dl": { $0 * 0.1791 }],
            "haemoglobin": ["g/dl": { $0 * 10 }],
            "vitamin_d": ["ng/ml": { $0 * 2.496 }],
            "vitamin_b12": ["pmol/l": { $0 * 1.355 }],
            "folate": ["nmol/l": { $0 / 2.266 }],
            "free_t4": ["ng/dl": { $0 * 12.87 }],
            "crp": ["mg/dl": { $0 * 10 }],
            "creatinine": ["mg/dl": { $0 * 88.42 }],
            "weight": ["lb": { $0 * 0.45359237 }, "lbs": { $0 * 0.45359237 }],
            "waist": ["in": { $0 * 2.54 }, "inch": { $0 * 2.54 }, "inches": { $0 * 2.54 }],
            "height": ["in": { $0 * 2.54 }, "inch": { $0 * 2.54 }, "inches": { $0 * 2.54 }],
        ]
    }()

    /// The converter from `unit` to `markerKey`'s canonical unit, or nil when the marker isn't in the
    /// catalog or the unit is unknown. An empty unit is NOT assumed canonical (nil) — the reviewer decides.
    public static func converter(unit: String, markerKey: String) -> ((Double) -> Double)? {
        guard let def = MarkerCatalog.definition(for: markerKey) else { return nil }
        let from = normalize(unit)
        guard !from.isEmpty else { return nil }
        let canonical = normalize(def.canonicalUnit)
        if from == canonical || synonyms[canonical]?.contains(from) == true { return { $0 } }
        return factors[markerKey]?[from]
    }

    /// True when `unit` already IS the canonical unit (or a same-quantity synonym): no conversion, so the printed
    /// value must be kept exactly as printed — re-rounding it to the catalog's decimals turned CRP 2.13 into 2.1.
    public static func isEquivalent(unit: String, markerKey: String) -> Bool {
        guard let def = MarkerCatalog.definition(for: markerKey) else { return false }
        let from = normalize(unit), canonical = normalize(def.canonicalUnit)
        return !from.isEmpty && (from == canonical || synonyms[canonical]?.contains(from) == true)
    }

    /// `value` in `markerKey`'s canonical unit, or nil when no conversion is known.
    public static func toCanonical(_ value: Double, unit: String, markerKey: String) -> Double? {
        converter(unit: unit, markerKey: markerKey).map { $0(value) }
    }
}
