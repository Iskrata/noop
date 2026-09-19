import Foundation
import StrandImport

/// Fork: the lab-report scan's network step. Sends already-redacted page images to the user's own OpenAI
/// key and returns the extracted rows (`LabReportScan` owns the prompt, schema and mapping). Gated exactly
/// like the Coach: the AI master switch, a configured OpenAI key, and the Coach's "use my data" consent.
extension AICoachEngine {

    enum LabScanGate: Equatable {
        case ready, aiOff, notOpenAI, noKey, noConsent

        /// What the scan screen tells the user when it can't run.
        var message: String? {
            switch self {
            case .ready:     return nil
            case .aiOff:     return String(localized: "AI features are switched off. Turn the Coach on in Settings to scan a report.")
            case .notOpenAI: return String(localized: "Report scanning uses OpenAI. Pick OpenAI as the Coach provider in Coach settings.")
            case .noKey:     return String(localized: "Add your OpenAI API key in Coach settings to scan a report.")
            case .noConsent: return String(localized: "Turn on \"Let the coach use my data\" in Coach settings first. A scan sends the report pages to OpenAI.")
            }
        }
    }

    var labScanGate: LabScanGate {
        guard CoachBriefScheduler.coachMasterEnabled else { return .aiOff }
        guard provider == .openAI else { return .notOpenAI }
        guard resolvedKey?.isEmpty == false else { return .noKey }
        guard dataConsent else { return .noConsent }
        return .ready
    }

    /// Upload the pages and decode the reply. Throws `AICoachError` for transport/provider failures and
    /// a decoding error when the reply isn't the schema's shape.
    func scanLabReport(jpegPages: [Data]) async throws -> [LabScanItem] {
        guard labScanGate == .ready, let key = resolvedKey else { throw AICoachError.noKey }
        let started = Date()
        NSLog("LabScan: uploading %d page(s), %d KB, model %@", jpegPages.count,
              jpegPages.reduce(0) { $0 + $1.count } / 1024, model)
        let json = try await OpenAIClient().extractJSON(
            key: key, model: model,
            systemPrompt: LabReportScan.systemPrompt, prompt: LabReportScan.userPrompt,
            jpegImages: jpegPages, schemaName: LabReportScan.schemaName, schema: LabReportScan.jsonSchema,
            session: session)
        let items = try LabReportScan.decode(json)
        NSLog("LabScan: %d row(s) in %.1fs", items.count, Date().timeIntervalSince(started))
        return items
    }
}
