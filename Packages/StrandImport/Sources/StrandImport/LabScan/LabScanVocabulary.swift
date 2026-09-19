import Foundation

// MARK: - Scan vocabulary: stable keys for common analytes outside the catalog (fork, iOS)
//
// `MarkerCatalog` holds ~30 markers; a real report prints 30–60 (full blood count with its differential,
// ESR, urea, uric acid, ALP, hormones…). Left to free names, the same test came back as "Basophils % (BASO %)"
// on one report and "BASO %" on the next, minting two `custom_*` keys and splitting its history. This list
// gives those analytes ONE stable `custom_<id>` key each (still category `.other` in the store): the model
// picks from it, and names it didn't map are matched here by alias (English, abbreviation, Bulgarian).
// Differential counts split by unit: "%" → `_pct`, anything else → `_abs`.
//
// Pure and deterministic.

public struct LabScanAnalyte: Sendable, Equatable {
    public let key: String
    public let displayName: String
    public let group: BiologyGroup
    /// Lowercase names; one alias may span several `_`-joined words (compared after `normalize`).
    let aliases: [String]
    /// nil for a plain marker; `.pct` / `.abs` for a differential count chosen by unit.
    let variant: Variant?

    enum Variant: Sendable { case pct, abs }
}

public enum LabScanVocabulary {

    private static func a(_ id: String, _ name: String, _ group: BiologyGroup, _ aliases: [String]) -> [LabScanAnalyte] {
        [LabScanAnalyte(key: "custom_" + id, displayName: name, group: group, aliases: aliases, variant: nil)]
    }

    /// A differential count: one alias list, two keys (percentage and absolute).
    private static func diff(_ id: String, _ name: String, _ aliases: [String]) -> [LabScanAnalyte] {
        [LabScanAnalyte(key: "custom_\(id)_pct", displayName: "\(name) %", group: .bloodCount, aliases: aliases, variant: .pct),
         LabScanAnalyte(key: "custom_\(id)_abs", displayName: "\(name) (count)", group: .bloodCount, aliases: aliases, variant: .abs)]
    }

    private static let plain: [[LabScanAnalyte]] = [
        a("wbc", "White blood cells (WBC)", .bloodCount, ["wbc", "white_blood_cells", "leukocytes", "leucocytes", "левкоцити", "лейкоцити"]),
        a("rbc", "Red blood cells (RBC)", .bloodCount, ["rbc", "red_blood_cells", "erythrocytes", "еритроцити"]),
        a("hematocrit", "Hematocrit (HCT)", .bloodCount, ["hct", "hematocrit", "haematocrit", "хематокрит"]),
        a("mcv", "MCV", .bloodCount, ["mcv"]),
        a("mch", "MCH", .bloodCount, ["mch"]),
        a("mchc", "MCHC", .bloodCount, ["mchc"]),
        a("rdw_cv", "RDW-CV", .bloodCount, ["rdw_cv"]),
        a("rdw_sd", "RDW-SD", .bloodCount, ["rdw_sd"]),
        a("platelets", "Platelets (PLT)", .bloodCount, ["plt", "platelets", "platelet_count", "тромбоцити"]),
        a("mpv", "MPV", .bloodCount, ["mpv"]),
        a("pdw", "PDW", .bloodCount, ["pdw"]),
        a("plateletcrit", "Plateletcrit (PCT)", .bloodCount, ["pct", "plateletcrit", "тромбокрит"]),
        a("p_lcr", "P-LCR", .bloodCount, ["p_lcr", "plcr"]),
        a("esr", "ESR", .inflammation, ["esr", "суе", "cye", "sed_rate", "erythrocyte_sedimentation_rate", "sedimentation_rate"]),
        a("urea", "Urea", .kidney, ["urea", "урея", "bun", "blood_urea_nitrogen"]),
        a("uric_acid", "Uric acid", .metabolic, ["uric_acid", "urate", "пикочна_киселина"]),
        a("insulin", "Insulin", .metabolic, ["insulin", "инсулин"]),
        a("alp", "Alkaline phosphatase (ALP)", .liver, ["alp", "alkaline_phosphatase", "алкална_фосфатаза", "алк_фосфатаза"]),
        a("total_bilirubin", "Bilirubin, total", .liver, ["total_bilirubin", "bilirubin_total", "общ_билирубин", "билирубин_общ"]),
        a("direct_bilirubin", "Bilirubin, direct", .liver, ["direct_bilirubin", "bilirubin_direct", "директен_билирубин", "билирубин_директен"]),
        a("albumin", "Albumin", .liver, ["albumin", "албумин"]),
        a("total_protein", "Total protein", .liver, ["total_protein", "общ_белтък"]),
        a("ldh", "LDH", .liver, ["ldh", "lactate_dehydrogenase"]),
        a("testosterone", "Testosterone", .hormones, ["testosterone", "total_testosterone", "тестостерон"]),
        a("free_testosterone", "Free testosterone", .hormones, ["free_testosterone", "свободен_тестостерон"]),
        a("estradiol", "Estradiol", .hormones, ["estradiol", "oestradiol", "e2", "естрадиол"]),
        a("cortisol", "Cortisol", .hormones, ["cortisol", "кортизол"]),
        a("shbg", "SHBG", .hormones, ["shbg", "sex_hormone_binding_globulin"]),
        a("free_t3", "Free T3", .hormones, ["ft3", "free_t3", "t3_free"]),
        a("magnesium", "Magnesium", .vitamins, ["magnesium", "mg", "магнезий"]),
        a("calcium", "Calcium", .vitamins, ["calcium", "ca", "калций"]),
        a("zinc", "Zinc", .vitamins, ["zinc", "zn", "цинк"]),
        a("chloride", "Chloride", .electrolytes, ["chloride", "cl", "хлор", "хлориди"]),
        a("vldl", "VLDL cholesterol", .heart, ["vldl", "vldl_c", "vldl_cholesterol"]),
        a("apob", "Apolipoprotein B", .heart, ["apob", "apo_b", "apolipoprotein_b"]),
        a("lpa", "Lipoprotein(a)", .heart, ["lpa", "lp_a", "lipoprotein_a"]),
        a("homocysteine", "Homocysteine", .heart, ["homocysteine", "хомоцистеин"]),
    ]

    private static let differentials: [[LabScanAnalyte]] = [
        diff("neutrophils", "Neutrophils", ["neut", "neu", "neutrophils", "anc", "неутрофили", "gran"]),
        diff("lymphocytes", "Lymphocytes", ["lymph", "lym", "lymphocytes", "лимфоцити"]),
        diff("monocytes", "Monocytes", ["mono", "mon", "monocytes", "моноцити"]),
        diff("eosinophils", "Eosinophils", ["eo", "eos", "eosinophils", "еозинофили"]),
        diff("basophils", "Basophils", ["baso", "bas", "basophils", "базофили"]),
    ]

    public static let all: [LabScanAnalyte] = (plain + differentials).flatMap { $0 }

    private static let byKey: [String: LabScanAnalyte] = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    public static func analyte(for key: String) -> LabScanAnalyte? { byKey[key] }

    /// The model's pick list (without the `custom_` prefix noise it doesn't need to see).
    static var promptLines: String {
        all.map { "\($0.key) = \($0.displayName)" }.joined(separator: "\n")
    }

    /// The stable key for a printed analyte name + unit, or nil when it isn't in the list. Urine tests never
    /// match (their leukocytes/erythrocytes/glucose are not the blood markers). Longer aliases win, so
    /// "rdw_cv" beats a stray shorter token.
    public static func resolve(name: String, unit: String?) -> String? {
        let norm = normalize(name)
        guard !norm.isEmpty, !isUrine(norm) else { return nil }
        let tokens = norm.split(separator: "_").map(String.init)
        let isPct = name.contains("%") || LabUnitConversion.normalize(unit ?? "") == "%"
        var best: (analyte: LabScanAnalyte, length: Int)?
        for analyte in all {
            if let variant = analyte.variant, (variant == .pct) != isPct { continue }
            for alias in analyte.aliases where contains(tokens, normalize(alias).split(separator: "_").map(String.init)) {
                // A short abbreviation ("pct", "mg", "eo") is ambiguous ("PCT" is also procalcitonin): it only
                // counts when every other word in the name also belongs to this analyte or is generic.
                if alias.count <= 3, !coversAll(tokens, analyte) { continue }
                if alias.count > (best?.length ?? 0) { best = (analyte, alias.count) }
            }
        }
        return best?.analyte.key
    }

    /// True for a urine test name.
    public static func isUrine(_ norm: String) -> Bool {
        norm.contains("urine") || norm.contains("урина") || norm.contains("urinalysis")
    }

    /// Lowercased, diacritics folded, every run of non-letters/digits → one `_`. Unlike the Lab Book's
    /// `matchNorm` this keeps non-ASCII letters, so Bulgarian names ("СУЕ", "Тромбокрит") can match.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("_") { out.append("_") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static let genericWords: Set<String> = ["abs", "absolute", "count", "total", "serum", "blood", "s", "b", "p"]

    private static func coversAll(_ tokens: [String], _ analyte: LabScanAnalyte) -> Bool {
        let words = Set(analyte.aliases.flatMap { normalize($0).split(separator: "_").map(String.init) })
        return tokens.allSatisfy { words.contains($0) || genericWords.contains($0) }
    }

    private static func contains(_ tokens: [String], _ seq: [String]) -> Bool {
        guard !seq.isEmpty, seq.count <= tokens.count else { return false }
        return (0...(tokens.count - seq.count)).contains { Array(tokens[$0..<($0 + seq.count)]) == seq }
    }
}
