import Foundation

// MARK: - Biology tab grouping (fork, iOS)
//
// The Lab Book's `LabMarkerCategory` is coarse (every blood result is `.bloodPanel`), so the Biology tab
// groups markers by body system the way WHOOP Advanced Labs / Bevel do. Catalog keys map directly;
// custom markers (a scan keeps unknown analytes under their own `custom_<slug>` key) are placed by
// keywords in that key, falling back to "Other". Organisational only — no clinical meaning.
//
// Pure and deterministic.

public enum BiologyGroup: String, CaseIterable, Sendable {
    // Declaration order is the Biology screen's section order (hormones first — the owner's pick).
    case hormones, heart, metabolic, bloodCount, iron, vitamins, inflammation, kidney, liver, electrolytes,
         urine, bloodPressure, body, other

    public var displayName: String {
        switch self {
        case .heart:         return "Heart & lipids"
        case .metabolic:     return "Metabolic"
        case .bloodCount:    return "Blood count"
        case .iron:          return "Iron"
        case .vitamins:      return "Vitamins & minerals"
        case .hormones:      return "Hormones & thyroid"
        case .inflammation:  return "Inflammation"
        case .kidney:        return "Kidney"
        case .liver:         return "Liver"
        case .electrolytes:  return "Electrolytes"
        case .urine:         return "Urine"
        case .bloodPressure: return "Blood pressure"
        case .body:          return "Body"
        case .other:         return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .heart:         return "heart.fill"
        case .metabolic:     return "flame.fill"
        case .bloodCount:    return "drop.fill"
        case .iron:          return "circle.hexagongrid.fill"
        case .vitamins:      return "pills.fill"
        case .hormones:      return "waveform.path.ecg"
        case .inflammation:  return "thermometer.medium"
        case .kidney:        return "drop.triangle.fill"
        case .liver:         return "cross.vial.fill"
        case .electrolytes:  return "bolt.fill"
        case .urine:         return "testtube.2"
        case .bloodPressure: return "heart.text.square.fill"
        case .body:          return "figure.stand"
        case .other:         return "square.grid.2x2.fill"
        }
    }

    private static let catalog: [String: BiologyGroup] = [
        "total_cholesterol": .heart, "ldl": .heart, "hdl": .heart, "triglycerides": .heart,
        "fasting_glucose": .metabolic, "hba1c": .metabolic,
        "ferritin": .iron, "iron": .iron, "transferrin_saturation": .iron,
        "haemoglobin": .bloodCount,
        "vitamin_d": .vitamins, "vitamin_b12": .vitamins, "folate": .vitamins,
        "tsh": .hormones, "free_t4": .hormones,
        "crp": .inflammation,
        "egfr": .kidney, "creatinine": .kidney,
        "alt": .liver, "ast": .liver, "ggt": .liver,
        "sodium": .electrolytes, "potassium": .electrolytes,
        "bp_systolic": .bloodPressure, "bp_diastolic": .bloodPressure, "resting_pulse": .bloodPressure,
        "weight": .body, "body_fat": .body, "waist": .body, "height": .body,
    ]

    /// Keyword → group for custom keys, checked in order (first hit wins), matched against `_`-delimited
    /// words of the key so "platelets" never matches inside another word.
    private static let keywords: [(BiologyGroup, [String])] = [
        (.heart, ["cholesterol", "ldl", "hdl", "vldl", "triglycerides", "lipoprotein", "lpa", "apob", "apoa1",
                  "apolipoprotein", "homocysteine"]),
        (.metabolic, ["glucose", "insulin", "hba1c", "a1c", "homa", "fructosamine", "uric", "c_peptide"]),
        (.bloodCount, ["wbc", "rbc", "hgb", "hct", "haematocrit", "hematocrit", "hemoglobin", "mcv", "mch", "mchc",
                       "rdw", "plt", "platelets", "platelet", "mpv", "neutrophils", "lymphocytes", "monocytes",
                       "eosinophils", "basophils", "leukocytes", "erythrocytes", "white", "red", "neu", "lym", "pdw",
                       "pct", "plateletcrit", "lcr",
                       "mon", "eos", "bas", "esr"]),
        (.iron, ["ferritin", "iron", "transferrin", "tibc", "uibc"]),
        (.vitamins, ["vitamin", "b12", "folate", "folic", "magnesium", "zinc", "calcium", "phosphorus",
                     "phosphate", "selenium", "copper", "omega"]),
        (.hormones, ["tsh", "t3", "t4", "ft3", "ft4", "testosterone", "estradiol", "oestradiol", "progesterone",
                     "cortisol", "dhea", "shbg", "lh", "fsh", "prolactin", "igf", "thyroglobulin", "tpo",
                     "psa", "amh"]),
        (.inflammation, ["crp", "hscrp", "fibrinogen", "il6"]),
        (.kidney, ["creatinine", "egfr", "urea", "bun", "cystatin", "albumin_creatinine", "microalbumin"]),
        (.liver, ["alt", "ast", "ggt", "alp", "bilirubin", "albumin", "protein", "ldh", "gpt", "got", "asat", "alat"]),
        (.electrolytes, ["sodium", "potassium", "chloride", "bicarbonate", "co2", "na", "k", "cl"]),
    ]

    /// The group a marker key belongs to.
    public static func of(_ markerKey: String) -> BiologyGroup {
        if let g = catalog[markerKey] { return g }
        if let analyte = LabScanVocabulary.analyte(for: markerKey) { return analyte.group }
        // Urine first: its leukocytes / glucose / protein must not fall into the blood groups below.
        if LabScanVocabulary.isUrine(markerKey.lowercased()) { return .urine }
        let words = Set(markerKey.lowercased().split(separator: "_").map(String.init))
        let joined = markerKey.lowercased()
        for (group, keys) in keywords {
            for k in keys where k.contains("_") ? joined.contains(k) : words.contains(k) {
                return group
            }
        }
        return .other
    }
}
