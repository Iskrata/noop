import XCTest
@testable import StrandImport

/// Fork: the AI lab-report scan's pure pieces — unit conversion, reference ranges, response mapping,
/// on-device redaction choices and Biology grouping.
final class LabReportScanTests: XCTestCase {

    // MARK: - Unit conversion

    func testConvertsCommonUSUnitsToCatalogUnits() throws {
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(130, unit: "mg/dL", markerKey: "ldl")), 3.362, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(150, unit: "mg/dl", markerKey: "triglycerides")), 1.694, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(90, unit: "mg/dL", markerKey: "fasting_glucose")), 4.996, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(5.5, unit: "%", markerKey: "hba1c")), 36.61, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(30, unit: "ng/mL", markerKey: "vitamin_d")), 74.88, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(1.0, unit: "mg/dL", markerKey: "creatinine")), 88.42, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(LabUnitConversion.toCanonical(14.5, unit: "g/dL", markerKey: "haemoglobin")), 145, accuracy: 0.001)
    }

    func testSynonymUnitsPassThroughAndMicroSignsFold() {
        XCTAssertEqual(LabUnitConversion.toCanonical(80, unit: "ng/mL", markerKey: "ferritin"), 80)   // = µg/L
        XCTAssertEqual(LabUnitConversion.toCanonical(80, unit: "μg/L", markerKey: "ferritin"), 80)    // Greek mu
        XCTAssertEqual(LabUnitConversion.toCanonical(80, unit: "mcg/L", markerKey: "ferritin"), 80)
        XCTAssertEqual(LabUnitConversion.toCanonical(2.1, unit: "µIU/mL", markerKey: "tsh"), 2.1)
        XCTAssertEqual(LabUnitConversion.toCanonical(140, unit: "mEq/L", markerKey: "sodium"), 140)
        XCTAssertEqual(LabUnitConversion.toCanonical(25, unit: "IU/L", markerKey: "alt"), 25)
        XCTAssertEqual(LabUnitConversion.toCanonical(95, unit: "mL/min/1,73 m²", markerKey: "egfr"), 95)
    }

    func testUnknownUnitOrCustomMarkerIsNotConverted() {
        XCTAssertNil(LabUnitConversion.toCanonical(5, unit: "furlongs", markerKey: "ldl"))
        XCTAssertNil(LabUnitConversion.toCanonical(5, unit: "", markerKey: "ldl"))
        XCTAssertNil(LabUnitConversion.toCanonical(5, unit: "mg/dL", markerKey: "custom_apob"))
    }

    // MARK: - Reference range

    func testParsesPrintedRanges() {
        XCTAssertEqual(LabReferenceRange.parse("3.0 - 5.0"), LabReferenceRange(low: 3, high: 5))
        XCTAssertEqual(LabReferenceRange.parse("3,5–5,1 mmol/L"), LabReferenceRange(low: 3.5, high: 5.1))
        XCTAssertEqual(LabReferenceRange.parse("4 to 10"), LabReferenceRange(low: 4, high: 10))
        XCTAssertEqual(LabReferenceRange.parse("< 5.2"), LabReferenceRange(low: nil, high: 5.2))
        XCTAssertEqual(LabReferenceRange.parse("≤5"), LabReferenceRange(low: nil, high: 5))
        XCTAssertEqual(LabReferenceRange.parse("Up to 40"), LabReferenceRange(low: nil, high: 40))
        XCTAssertEqual(LabReferenceRange.parse("> 1.0"), LabReferenceRange(low: 1, high: nil))
        XCTAssertNil(LabReferenceRange.parse("negative"))
        XCTAssertNil(LabReferenceRange.parse("5 - 3"))    // inverted
        XCTAssertNil(LabReferenceRange.parse(nil))
    }

    func testStatusAndBarPosition() throws {
        let r = try XCTUnwrap(LabReferenceRange(low: 3, high: 5))
        XCTAssertEqual(r.status(2.9), .below)
        XCTAssertEqual(r.status(3), .inRange)
        XCTAssertEqual(r.status(5), .inRange)
        XCTAssertEqual(r.status(5.1), .above)
        XCTAssertEqual(r.band, 0.25...0.75)
        XCTAssertEqual(r.position(4), 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.position(3), 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.position(100), 0.97)             // clamped inside the track
        let upper = try XCTUnwrap(LabReferenceRange(low: nil, high: 5))
        XCTAssertEqual(upper.band, 0...0.75)
        XCTAssertEqual(upper.position(5), 0.75, accuracy: 1e-9)
        XCTAssertEqual(upper.text(decimals: 1), "< 5.0")
        XCTAssertEqual(r.text(decimals: 2), "3.00–5.00")
    }

    // MARK: - Response mapping

    func testDecodesTheStrictSchemaEnvelope() throws {
        let json = """
        {"markers":[{"name":"LDL-C","value":"130","unit":"mg/dL","referenceLow":null,"referenceHigh":100,
        "referenceText":"<100","takenAt":"2026-09-01","catalogKey":"ldl","confidence":"high"}]}
        """
        let items = try LabReportScan.decode(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].referenceHigh, 100)
        XCTAssertNil(items[0].referenceLow)
    }

    func testCatalogMarkerIsConvertedWithItsRange() throws {
        let item = LabScanItem(name: "LDL cholesterol", value: "130", unit: "mg/dL", referenceLow: nil,
                               referenceHigh: 100, referenceText: "<100", takenAt: "2026-09-01", catalogKey: "ldl")
        let c = try XCTUnwrap(LabReportScan.candidate(item, id: "a"))
        XCTAssertEqual(c.markerKey, "ldl")
        XCTAssertEqual(c.category, .bloodPanel)
        XCTAssertEqual(c.valueInput, "3.36")
        XCTAssertEqual(c.unit, "mmol/L")
        XCTAssertEqual(c.referenceText, "< 2.59")          // converted bound, not the mg/dL text
        XCTAssertEqual(c.day, "2026-09-01")
        XCTAssertTrue(c.flags.isEmpty)
    }

    func testModelKeyIsIgnoredWhenNotInCatalogAndNameResolverIsUsed() throws {
        let item = LabScanItem(name: "Hemoglobin", value: "14,5", unit: "g/dL", takenAt: "2026-09-01",
                               catalogKey: "not_a_key")
        let c = try XCTUnwrap(LabReportScan.candidate(item, id: "a"))
        XCTAssertEqual(c.markerKey, "haemoglobin")
        XCTAssertEqual(c.valueInput, "145")
        XCTAssertEqual(c.unit, "g/L")
    }

    func testUnknownMarkerKeepsItsOwnKeyUnderOther() throws {
        let item = LabScanItem(name: "White blood cells (WBC)", value: "6.5", unit: "10^9/L", referenceLow: 4,
                               referenceHigh: 10, referenceText: "4.0 - 10.0", takenAt: "2026-09-01")
        let c = try XCTUnwrap(LabReportScan.candidate(item, id: "a"))
        XCTAssertEqual(c.markerKey, "custom_white_blood_cells_wbc")
        XCTAssertEqual(c.category, .other)
        XCTAssertEqual(c.unit, "10^9/L")
        XCTAssertEqual(c.referenceText, "4.0 - 10.0")
        XCTAssertEqual(c.flags, [.unmapped])
    }

    func testFlagsLowConfidenceUnknownUnitTextValueAndMissingDate() throws {
        let odd = LabScanItem(name: "LDL", value: "3.1", unit: "mmol/dL", catalogKey: "ldl", confidence: "low")
        let c = try XCTUnwrap(LabReportScan.candidate(odd, id: "a"))
        XCTAssertEqual(c.flags, [.lowConfidence, .unitNotConverted, .noDate])
        XCTAssertEqual(c.unit, "mmol/dL")                 // kept as printed

        let text = LabScanItem(name: "Urine glucose", value: "negative", takenAt: "2026-09-01")
        let t = try XCTUnwrap(LabReportScan.candidate(text, id: "b"))
        XCTAssertTrue(t.flags.contains(.notNumeric))
        XCTAssertNil(t.parsedValue.value)
        XCTAssertEqual(t.parsedValue.text, "negative")
    }

    func testComparatorValuesKeepTheirTextAndConvert() throws {
        XCTAssertEqual(LabReportScan.parseValue("<0.5").value, 0.5)
        XCTAssertEqual(LabReportScan.parseValue("<0.5").text, "<0.5")
        XCTAssertEqual(LabReportScan.parseValue("5,2").value, 5.2)
        XCTAssertNil(LabReportScan.parseValue("5,2").text)
        let crp = LabScanItem(name: "CRP", value: "<0.1", unit: "mg/dL", takenAt: "2026-09-01", catalogKey: "crp")
        XCTAssertEqual(LabReportScan.candidate(crp, id: "a")?.valueInput, "<1.0")
    }

    func testDuplicatesInOneScanAreFlaggedAndClearedAfterRemap() throws {
        let a = LabScanItem(name: "Glucose", value: "5.1", unit: "mmol/L", takenAt: "2026-09-01", catalogKey: "fasting_glucose")
        let b = LabScanItem(name: "Glucose (fasting)", value: "5.0", unit: "mmol/L", takenAt: "2026-09-01", catalogKey: "fasting_glucose")
        var rows = LabReportScan.candidates([a, b])
        XCTAssertTrue(rows.allSatisfy { $0.flags.contains(.duplicate) })
        rows[1] = try XCTUnwrap(LabReportScan.candidate(b, id: rows[1].id, forcedKey: "custom_glucose_fasting"))
        LabReportScan.markDuplicates(&rows)
        XCTAssertFalse(rows[0].flags.contains(.duplicate))
    }

    func testReportNameRoundTripsThroughTheNote() {
        XCTAssertEqual(LabReportScan.reportName(fromNote: LabReportScan.reportNamePrefix + "Platelets"), "Platelets")
        XCTAssertNil(LabReportScan.reportName(fromNote: "WHOOP: Optimal"))
    }

    func testSchemaIsStrictObjectWithEveryFieldRequired() throws {
        let schema = LabReportScan.jsonSchema
        let items = try XCTUnwrap(((schema["properties"] as? [String: Any])?["markers"] as? [String: Any])?["items"] as? [String: Any])
        let required = try XCTUnwrap(items["required"] as? [String])
        let props = try XCTUnwrap(items["properties"] as? [String: Any])
        XCTAssertEqual(Set(required), Set(props.keys))
        XCTAssertEqual(items["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: schema))
    }

    // MARK: - Redaction

    func testSensitiveLinesAreDetected() {
        XCTAssertTrue(LabReportRedaction.isSensitive("Patient: John Smith"))
        XCTAssertTrue(LabReportRedaction.isSensitive("Date of birth 01.02.1990"))
        XCTAssertTrue(LabReportRedaction.isSensitive("ЕГН 9001011234"))
        XCTAssertTrue(LabReportRedaction.isSensitive("Пациент: Иван Иванов"))
        XCTAssertTrue(LabReportRedaction.isSensitive("д-р Петрова"))
        XCTAssertTrue(LabReportRedaction.isSensitive("john@example.com"))
        XCTAssertTrue(LabReportRedaction.isSensitive("+359 88 123 4567"))
        XCTAssertTrue(LabReportRedaction.isSensitive("Sample 20260901123"))
        // Results, ranges and the sample date stay readable.
        XCTAssertFalse(LabReportRedaction.isSensitive("Platelets 250 150 - 400"))
        XCTAssertFalse(LabReportRedaction.isSensitive("Показател Резултат"))
        XCTAssertFalse(LabReportRedaction.isSensitive("LDL cholesterol 3.36 mmol/L"))
        XCTAssertFalse(LabReportRedaction.isSensitive("Collected 2026-09-01"))
        XCTAssertFalse(LabReportRedaction.isSensitive("Hematocrit 0.450 L/L"))
    }

    func testLabelBlanksItsValueOnTheSameRowAndBelowAColon() {
        let lines: [LabReportRedaction.Line] = [
            .init(text: "Name", x: 0.05, y: 0.10, width: 0.10, height: 0.02),
            .init(text: "Ivan Petrov", x: 0.30, y: 0.101, width: 0.20, height: 0.02),   // same row → blank
            .init(text: "Doctor:", x: 0.05, y: 0.20, width: 0.10, height: 0.02),
            .init(text: "Maria Georgieva", x: 0.05, y: 0.225, width: 0.20, height: 0.02), // below colon → blank
            .init(text: "Glucose 5.1 mmol/L", x: 0.05, y: 0.50, width: 0.40, height: 0.02),
        ]
        XCTAssertEqual(LabReportRedaction.linesToRedact(lines), [0, 1, 2, 3])
    }

    // MARK: - Biology grouping

    func testGroupsCatalogAndCustomKeys() {
        XCTAssertEqual(BiologyGroup.of("ldl"), .heart)
        XCTAssertEqual(BiologyGroup.of("hba1c"), .metabolic)
        XCTAssertEqual(BiologyGroup.of("custom_white_blood_cells_wbc"), .bloodCount)
        XCTAssertEqual(BiologyGroup.of("custom_platelets"), .bloodCount)
        XCTAssertEqual(BiologyGroup.of("custom_pct_plateletcrit"), .bloodCount)
        XCTAssertEqual(BiologyGroup.of("custom_p_lcr"), .bloodCount)
        XCTAssertEqual(BiologyGroup.of("custom_pdw"), .bloodCount)
        XCTAssertEqual(BiologyGroup.of("custom_c_reactive_protein_crp"), .inflammation)
        XCTAssertEqual(BiologyGroup.of("custom_testosterone_total"), .hormones)
        XCTAssertEqual(BiologyGroup.of("custom_total_protein"), .liver)
        XCTAssertEqual(BiologyGroup.of("custom_magnesium"), .vitamins)
        XCTAssertEqual(BiologyGroup.of("custom_something_else"), .other)
    }
}
