import Foundation

// MARK: - AI lab-report scan: response contract + mapping (fork, iOS)
//
// The Biology tab's "Scan lab report" sends redacted page images to the user's own OpenAI key with a strict
// JSON-schema response (`jsonSchema`). This file owns that contract and turns the reply into editable
// review candidates: each extracted row is mapped onto a `MarkerCatalog` key (the model's `catalogKey`
// pick when valid, else the Lab Book's own name resolver), converted to the catalog's unit, and flagged
// when a person should look at it. Nothing here saves — the review screen does, after the user confirms.
//
// Pure and deterministic — no network, no DB.

/// One row exactly as the model returned it.
public struct LabScanItem: Codable, Equatable, Sendable {
    public var name: String
    /// As printed, comparator included ("5.2", "<0.5", "negative").
    public var value: String
    public var unit: String?
    public var referenceLow: Double?
    public var referenceHigh: Double?
    public var referenceText: String?
    /// "yyyy-MM-dd" sample date, when printed.
    public var takenAt: String?
    /// The model's catalog pick, or nil.
    public var catalogKey: String?
    /// "high" or "low".
    public var confidence: String?

    public init(name: String, value: String, unit: String? = nil, referenceLow: Double? = nil,
                referenceHigh: Double? = nil, referenceText: String? = nil, takenAt: String? = nil,
                catalogKey: String? = nil, confidence: String? = "high") {
        self.name = name; self.value = value; self.unit = unit
        self.referenceLow = referenceLow; self.referenceHigh = referenceHigh; self.referenceText = referenceText
        self.takenAt = takenAt; self.catalogKey = catalogKey; self.confidence = confidence
    }
}

/// Why a review row deserves a second look.
public enum LabScanFlag: String, Sendable, CaseIterable {
    case lowConfidence, unmapped, unitNotConverted, notNumeric, noDate, duplicate
}

/// One editable review row. `valueInput` / `unit` / `referenceText` / `day` are what the user edits;
/// `item` is kept so re-mapping to another marker re-derives the conversion from the printed values.
public struct LabScanCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let item: LabScanItem
    public var markerKey: String
    public var category: LabMarkerCategory
    public var valueInput: String
    public var unit: String
    public var referenceText: String?
    public var day: String?
    public var flags: Set<LabScanFlag>

    /// The numeric reading and the text kept beside it ("<0.5" keeps its comparator as text).
    public var parsedValue: (value: Double?, text: String?) { LabReportScan.parseValue(valueInput) }
    public var isCatalogMarker: Bool { MarkerCatalog.definition(for: markerKey) != nil }
}

public enum LabReportScan {

    /// Provenance id stored on every saved reading.
    public static let sourceId = "ai-scan"
    /// The note prefix carrying the name printed on the report (custom markers display it).
    public static let reportNamePrefix = "Report name: "
    public static let schemaName = "lab_report"

    // MARK: Request contract

    /// Catalog markers the model may map onto (blood panel + blood pressure — the ones a lab prints).
    public static var scannableCatalog: [MarkerDefinition] {
        MarkerCatalog.builtIn.filter { $0.category == .bloodPanel || $0.category == .bloodPressure }
    }

    public static var systemPrompt: String {
        let keys = scannableCatalog.map { "\($0.key) = \($0.displayName) (\($0.canonicalUnit))" }.joined(separator: "\n")
        return """
        You read photos of a medical laboratory report and extract every measured result. Some areas are \
        blacked out for privacy; ignore them. Never invent or estimate a value that is not printed.
        For each result row return:
        - name: the analyte name as printed (translate to English if the report is in another language, \
        keep the abbreviation, e.g. "White blood cells (WBC)").
        - value: the result exactly as printed, including any "<" or ">" (e.g. "5.2", "<0.5", "negative").
        - unit: the unit as printed, or null.
        - referenceLow / referenceHigh: the numeric bounds of the printed reference interval in the same unit, \
        null when a bound is absent.
        - referenceText: the reference interval exactly as printed, or null.
        - takenAt: the sample collection date as YYYY-MM-DD (else the report date), or null.
        - catalogKey: one of the keys below ONLY when the analyte is clearly the same measurement, else null. \
        Use fasting_glucose for plasma/serum glucose, hba1c for glycated haemoglobin, vitamin_d for 25-OH vitamin D.
        - confidence: "low" when any field was hard to read or you are unsure, otherwise "high".
        Catalog keys:
        \(keys)
        """
    }

    public static let userPrompt = "Extract every lab result from these report pages."

    /// The strict JSON schema for OpenAI structured outputs (object root, every field required, nullables typed).
    public static var jsonSchema: [String: Any] {
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let nullableNumber: [String: Any] = ["type": ["number", "null"]]
        let item: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["name", "value", "unit", "referenceLow", "referenceHigh", "referenceText",
                         "takenAt", "catalogKey", "confidence"],
            "properties": [
                "name": ["type": "string"],
                "value": ["type": "string"],
                "unit": nullableString,
                "referenceLow": nullableNumber,
                "referenceHigh": nullableNumber,
                "referenceText": nullableString,
                "takenAt": nullableString,
                "catalogKey": ["anyOf": [["type": "string", "enum": scannableCatalog.map(\.key)], ["type": "null"]]],
                "confidence": ["type": "string", "enum": ["high", "low"]],
            ] as [String: Any],
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["markers"],
            "properties": ["markers": ["type": "array", "items": item]],
        ]
    }

    // MARK: Response → candidates

    private struct Envelope: Decodable { let markers: [LabScanItem] }

    /// Decode the model's JSON reply (`{"markers":[…]}`).
    public static func decode(_ json: String) throws -> [LabScanItem] {
        try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).markers
    }

    /// Map every item onto a review candidate and mark duplicates (same marker + day twice in one scan —
    /// only one of them can be saved under the natural key).
    public static func candidates(_ items: [LabScanItem]) -> [LabScanCandidate] {
        var out = items.enumerated().compactMap { candidate($1, id: "scan-\($0)") }
        markDuplicates(&out)
        return out
    }

    /// Recompute the duplicate flag across the current rows (after a remap or delete).
    public static func markDuplicates(_ rows: inout [LabScanCandidate]) {
        var seen: [String: Int] = [:]
        for r in rows { seen[r.markerKey + "\u{1}" + (r.day ?? ""), default: 0] += 1 }
        for i in rows.indices {
            if seen[rows[i].markerKey + "\u{1}" + (rows[i].day ?? ""), default: 0] > 1 {
                rows[i].flags.insert(.duplicate)
            } else {
                rows[i].flags.remove(.duplicate)
            }
        }
    }

    /// One candidate from one item. `forcedKey` re-maps it (the reviewer picked another marker, or "keep
    /// as its own"). nil for a row with no usable name.
    public static func candidate(_ item: LabScanItem, id: String, forcedKey: String? = nil) -> LabScanCandidate? {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let key = forcedKey ?? resolveKey(item)
        guard !key.isEmpty else { return nil }
        let def = MarkerCatalog.definition(for: key)
        var flags: Set<LabScanFlag> = []
        if item.confidence?.lowercased() == "low" { flags.insert(.lowConfidence) }
        if def == nil { flags.insert(.unmapped) }

        let printedUnit = (item.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = parseValue(item.value)
        var valueInput = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
        var unit = printedUnit
        var low = item.referenceLow
        var high = item.referenceHigh
        var converted = false

        if let def, parsed.value != nil {
            if let convert = LabUnitConversion.converter(unit: printedUnit, markerKey: key) {
                let v = convert(parsed.value!)
                valueInput = comparatorPrefix(valueInput) + format(v, decimals: def.decimals)
                unit = def.canonicalUnit
                low = low.map(convert)
                high = high.map(convert)
                converted = LabUnitConversion.normalize(printedUnit) != LabUnitConversion.normalize(def.canonicalUnit)
            } else {
                flags.insert(.unitNotConverted)
            }
        }
        if parsed.value == nil { flags.insert(.notNumeric) }

        let referenceText: String? = {
            // The printed text wins when the Biology bar can read it back and the value wasn't converted (it
            // would be in the wrong unit then); otherwise the numeric bounds; otherwise the printed text as is.
            let printed = item.referenceText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if !converted, let printed, LabReferenceRange.parse(printed) != nil { return printed }
            if let range = LabReferenceRange(low: low, high: high) {
                return range.text(decimals: def?.decimals ?? decimalsIn(item))
            }
            return converted || printed?.isEmpty != false ? nil : printed
        }()

        let day = item.takenAt.flatMap { LabMarkerCsvImport.canonicalDay($0) }
        if day == nil { flags.insert(.noDate) }

        return LabScanCandidate(id: id, item: item, markerKey: key,
                                category: def?.category ?? .other,
                                valueInput: valueInput, unit: unit, referenceText: referenceText,
                                day: day, flags: flags)
    }

    /// The model's catalog pick when it names a real catalog key, else the Lab Book's name resolver
    /// (catalog name / alias, or the same `custom_<slug>` key a hand-added marker gets).
    static func resolveKey(_ item: LabScanItem) -> String {
        if let k = item.catalogKey, MarkerCatalog.definition(for: k) != nil { return k }
        if let k = LabMarkerCsvImport.resolveMarker(item.name).key { return k }
        return LabMarkerCsvImport.customKey(item.name)
    }

    /// The marker's own `custom_<slug>` key (the reviewer chose "keep as its own marker").
    public static func ownKey(for name: String) -> String {
        LabMarkerCsvImport.customKey(name)
    }

    // MARK: Values

    /// "5.2" → (5.2, nil); "<0.5" → (0.5, "<0.5"); "5,2 mmol/L" → (5.2, nil); "negative" → (nil, "negative").
    public static func parseValue(_ raw: String) -> (value: Double?, text: String?) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return (nil, nil) }
        let prefix = comparatorPrefix(t)
        let rest = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard let v = LabMarkerCsvImport.parseValue(rest) else { return (nil, t) }
        return (v, prefix.isEmpty ? nil : t)
    }

    /// The report name carried in a scanned reading's note, if any.
    public static func reportName(fromNote note: String?) -> String? {
        guard let note, note.hasPrefix(reportNamePrefix) else { return nil }
        let name = note.dropFirst(reportNamePrefix.count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func comparatorPrefix(_ s: String) -> String {
        for p in ["<=", ">=", "≤", "≥", "<", ">"] where s.hasPrefix(p) { return p }
        return ""
    }

    private static func format(_ v: Double, decimals: Int) -> String {
        decimals <= 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
    }

    /// Decimals for a custom marker's range text: as many as the printed value shows (max 3).
    private static func decimalsIn(_ item: LabScanItem) -> Int {
        guard let dot = item.value.firstIndex(where: { $0 == "." || $0 == "," }) else { return 0 }
        return min(3, item.value[item.value.index(after: dot)...].prefix(while: \.isNumber).count)
    }
}
