import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport

/// Fork: the "Scan lab report" sheet. Pick photos or a PDF → on-device OCR blanks personal lines (the user
/// sees and can adjust every box) → the redacted pages go to the user's own OpenAI key → the results are
/// saved straight away (no review step, the owner's call) and summarised, flagged rows called out.
/// Gated by the Coach's AI switch, OpenAI key and "use my data" consent (`AICoachEngine.labScanGate`).
struct LabScanFlowView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case pick, preparing, preview, uploading, saved(count: Int, day: String, flagged: [String]), failed(String)
    }

    @State private var step: Step = .pick
    @State private var pages: [LabScanPage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPDFPicker = false

    var body: some View {
        NavigationStack {
            content
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationTitle("Scan lab report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.foregroundStyle(StrandPalette.accent)
                    }
                }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showingPDFPicker, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): Task { await prepare(LabScanImages.pages(fromPDF: url)) }
            case .failure(let error): NSLog("LabScan: PDF picker failed - \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .pick:
            pickStep
        case .preparing:
            progress("Reading the pages on this iPhone…")
        case .preview:
            previewStep
        case .uploading:
            progress("Reading your results… this can take a minute.")
        case .saved(let count, let day, let flagged):
            savedStep(count: count, day: day, flagged: flagged)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 32))
                    .foregroundStyle(HealthMonitorSection.outOfRangeColor)
                Text(message).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                NoopButton("Try again", kind: .secondary) { step = pages.isEmpty ? .pick : .preview }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Steps

    private var pickStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                NoopCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photograph or pick your report").font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text("Your name, birth date, ID, address, phone and doctor are blanked on this iPhone before anything is sent. You check every page first. Up to \(LabScanImages.maxPages) pages.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let message = coach.labScanGate.message {
                    NoopCard(tint: HealthMonitorSection.outOfRangeColor) {
                        Label(message, systemImage: "lock.fill")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PhotosPicker(selection: $photoItems, maxSelectionCount: LabScanImages.maxPages, matching: .images) {
                    Label("Choose photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NoopButtonStyle(.primary, fullWidth: true))
                NoopButton("Choose a PDF", systemImage: "doc.richtext", kind: .secondary, fullWidth: true) {
                    showingPDFPicker = true
                }
            }
            .padding(16)
        }
    }

    private var previewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("Black boxes are removed before upload. Tap any text line to hide it, or a black box to show it.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach($pages) { $page in
                    LabRedactionPreview(page: $page)
                }
                NoopButton("Send \(pages.count == 1 ? "1 page" : "\(pages.count) pages") to OpenAI",
                           systemImage: "arrow.up.circle.fill", kind: .primary, fullWidth: true) {
                    Task { await upload() }
                }
                .disabled(coach.labScanGate != .ready)
                if let message = coach.labScanGate.message {
                    Text(message).font(StrandFont.footnote).foregroundStyle(HealthMonitorSection.outOfRangeColor)
                }
            }
            .padding(16)
        }
    }

    private func savedStep(count: Int, day: String, flagged: [String]) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            Label(count == 1 ? "Saved 1 result" : "Saved \(count) results", systemImage: "checkmark.circle.fill")
                .font(StrandFont.headline).foregroundStyle(HealthMonitorSection.inRangeColor)
            Text("From the report dated \(LabBookFormat.dayFromKey(day)). Open a marker in Biology to edit or delete a reading.")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !flagged.isEmpty {
                NoopCard(tint: HealthMonitorSection.outOfRangeColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Worth a look").font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(HealthMonitorSection.outOfRangeColor)
                        ForEach(flagged, id: \.self) { Text($0).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary) }
                    }
                }
            }
            NoopButton("Done", kind: .primary, fullWidth: true) { dismiss() }
            Spacer()
        }
        .padding(16)
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            ProgressView().tint(StrandPalette.accent)
            Text(text).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Work

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        step = .preparing
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        await prepare(images.map(LabScanImages.normalized))
    }

    private func prepare(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            step = .failed(String(localized: "Couldn't open that file. Try a photo or another PDF."))
            return
        }
        step = .preparing
        var out: [LabScanPage] = []
        for image in images { out.append(await LabScanImages.page(image)) }
        pages = out
        step = .preview
    }

    private func upload() async {
        let jpegs = pages.compactMap(LabScanImages.redactedJPEG)
        guard !jpegs.isEmpty else { return }
        step = .uploading
        do {
            let items = try await coach.scanLabReport(jpegPages: jpegs)
            let rows = LabReportScan.candidates(items)
            guard !rows.isEmpty else {
                step = .failed(String(localized: "No lab results were found on these pages."))
                return
            }
            await save(rows)
        } catch {
            NSLog("LabScan: failed - \(error)")
            step = .failed(error.localizedDescription)
        }
    }

    private func save(_ rows: [LabScanCandidate]) async {
        guard let store = await repo.storeHandle() else { return }
        let reportDay = LabScanCandidate.reportDay(rows)
        let markers = rows.map { $0.labMarkerRow(deviceId: repo.deviceId, reportDay: reportDay) }
        let flagged = rows.filter { !$0.flags.subtracting([.noDate, .unmapped]).isEmpty }.map(\.flagSummary)
        do {
            let written = try await store.upsertLabMarkers(markers)
            NSLog("LabScan: saved %d reading(s), %d flagged", written, flagged.count)
            await repo.refresh()
            step = .saved(count: markers.count, day: reportDay, flagged: flagged)
        } catch {
            NSLog("LabScan: save failed - \(error)")
            step = .failed(String(localized: "Couldn't save the readings: \(error.localizedDescription)"))
        }
    }
}
