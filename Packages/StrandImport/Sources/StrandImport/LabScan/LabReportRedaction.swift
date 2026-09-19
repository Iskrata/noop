import Foundation

// MARK: - On-device redaction of a lab report before upload (fork, iOS)
//
// Before a scanned report leaves the phone, the app runs Apple's on-device text recognition and paints
// over every line that looks personal: the patient's name, date of birth, national ID (EGN), address,
// phone, e-mail, and the doctor/requester. This file decides WHICH recognized lines to blank; the app
// draws the boxes and shows them to the user, who can toggle any line before anything is sent.
//
// Heuristics, deliberately biased towards blanking: a label ("Patient:", "ЕГН", "Dr.") blanks its own line
// and the value next to it on the same row (or the line right below when the label ends the row);
// e-mail addresses, phone numbers and long digit runs (IDs, barcodes) blank their line. Sample dates and
// results are left alone — the extraction needs them.
//
// Pure and deterministic — no Vision, no UIKit.

public enum LabReportRedaction {

    /// A recognized text line with its box in normalized page coordinates (0…1, origin top-left).
    public struct Line: Equatable, Sendable {
        public let text: String
        public let x: Double, y: Double, width: Double, height: Double
        public init(text: String, x: Double, y: Double, width: Double, height: Double) {
            self.text = text; self.x = x; self.y = y; self.width = width; self.height = height
        }
        var midY: Double { y + height / 2 }
        var maxX: Double { x + width }
    }

    /// Label words (English + Bulgarian) that introduce personal details. Matched as whole words on the
    /// lowercased line.
    private static let labelPatterns: [String] = [
        "name", "surname", "patient", "dob", "date of birth", "birth ?date", "born", "address", "street",
        "phone", "tel", "mobile", "e-?mail", "doctor", "physician", "dr", "md", "referr(?:ing|ed)",
        "ordered by", "requested by", "signature", "signed", "id", "mrn", "ssn", "personal (?:no|number|id)",
        "insurance", "policy",
        "име", "имена", "фамилия", "пациент", "егн", "лнч", "дата на раждане", "роден", "родена", "адрес",
        "ул", "телефон", "тел", "имейл", "лекар", "д-р", "др", "доктор", "назначил", "изпращащ", "насочен",
        "подпис", "здравноосигурителен", "лични данни",
    ]

    private static let labelRegex: NSRegularExpression = {
        // Word boundaries that also work for Cyrillic: not preceded/followed by a letter or digit.
        let alternation = labelPatterns.joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(alternation))(?![\\p{L}\\p{N}])",
                                        options: [.caseInsensitive])
    }()

    private static let patternRegexes: [NSRegularExpression] = [
        "[\\w.+-]+@[\\w-]+\\.[\\w.]+",                         // e-mail
        "(?<![0-9.,])[0-9]{7,}(?![0-9.,])",                    // ID / EGN / barcode: 7+ digits, no decimal
        "\\+[0-9]{1,3}[ -]?[0-9]{2,4}[ -]?[0-9]{3}[ -]?[0-9]{3,4}", // international phone
        "(?<![0-9.,])0[0-9]{2,3}[ /-][0-9]{3}[ -]?[0-9]{3,4}(?![0-9.,])", // local phone "088 123 4567"
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// True when the line itself carries a personal-detail label.
    public static func hasLabel(_ text: String) -> Bool {
        matches(labelRegex, text)
    }

    /// True when the line should be blanked on its own (label, e-mail, phone or ID).
    public static func isSensitive(_ text: String) -> Bool {
        hasLabel(text) || patternRegexes.contains { matches($0, text) }
    }

    /// Indices of the lines to blank: every sensitive line, the lines to the right of a label on the same
    /// row, and — for a label that ends its row with a colon — the nearest line directly below it.
    public static func linesToRedact(_ lines: [Line]) -> Set<Int> {
        var out: Set<Int> = []
        for (i, line) in lines.enumerated() where isSensitive(line.text) {
            out.insert(i)
            guard hasLabel(line.text) else { continue }
            let sameRow = lines.indices.filter { j in
                j != i && lines[j].x >= line.x + line.width * 0.5 && abs(lines[j].midY - line.midY) < line.height * 0.6
            }
            out.formUnion(sameRow)
            if sameRow.isEmpty, line.text.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                let below = lines.indices
                    .filter { j in
                        let gap = lines[j].y - (line.y + line.height)
                        return gap >= -line.height * 0.2 && gap < line.height * 1.5
                            && lines[j].x < line.maxX && lines[j].maxX > line.x
                    }
                    .min { lines[$0].y < lines[$1].y }
                if let below { out.insert(below) }
            }
        }
        return out
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
