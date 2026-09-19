import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

/// Fork: Biology — the user's bloodwork the way WHOOP Advanced Labs / Bevel show it. Markers are grouped by
/// body system, each with its latest value, where it sits in the reference range printed on the user's own
/// report, and its trend; tapping one opens its history chart. Reads and writes the same Lab Book store
/// (`labMarker`), so a scanned or hand-entered reading appears in both places.
struct BiologyView: View {
    @EnvironmentObject var repo: Repository

    @State private var markers: [BiologyMarker] = []
    /// Every marker over its full history — the detail sheet reads this whatever report is selected.
    @State private var allMarkers: [BiologyMarker] = []
    /// Test dates with results, newest first; `selectedDay` nil = "Latest results" (each marker's latest).
    @State private var reportDays: [String] = []
    @State private var selectedDay: String?
    /// Grouped once per load (not per body pass — see BiologyMarker).
    @State private var groups: [(BiologyGroup, [BiologyMarker])] = []
    @State private var loaded = false
    @State private var loadedRows: [LabMarkerRow] = []
    @State private var showingScan = false
    @State private var showingEditor = false
    @State private var detailKey: String?

    /// Categories that aren't results (imaging notes, appointment notes) stay in the Lab Book only.
    private static let excluded: Set<String> = [LabMarkerCategory.imaging.rawValue, LabMarkerCategory.appointmentNote.rawValue]

    var body: some View {
        ScreenScaffold(title: "Lab", subtitle: "Your bloodwork, read from your own lab reports.",
                       onRefresh: { await load() }, lazy: true, topBackground: liquidScaffoldSky()) {
            // Flat children, no wrapping VStack: the scaffold's LazyVStack (spacing 20) then builds each
            // header and card on demand as it scrolls in. Paddings restore the section/item rhythm.
            if reportDays.count > 1 { reportPicker }
            BiologySummaryCard(markers: markers,
                               onScan: { showingScan = true },
                               onAdd: { showingEditor = true })
            if loaded, let day = selectedDay ?? reportDays.first { BiologyCoachTips(day: day, rows: loadedRows) }
            if !loaded {
                ComingSoon(what: "Reading your results…", symbol: "drop.fill")
            } else if markers.isEmpty {
                Text("No results yet. Scan a lab report or add a reading to start.")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            } else {
                ForEach(groups, id: \.0) { group, items in
                    SectionHeader(LocalizedStringKey(group.displayName),
                                  overline: items.count == 1 ? "1 marker" : "\(items.count) markers")
                        .padding(.top, NoopMetrics.sectionGap - 20)
                    ForEach(items) { marker in
                        Button { detailKey = marker.key } label: { BiologyMarkerCard(marker: marker) }
                            .buttonStyle(LiquidPressStyle())
                            .padding(.top, NoopMetrics.gap - 20)
                    }
                }
            }
            Text("Ranges are the ones printed on your own report. NOOP doesn't diagnose; ask your doctor what a result means for you.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopMetrics.sectionGap - 20)
        }
        .task(id: repo.refreshSeq) { await load() }
        .sheet(isPresented: $showingScan) { LabScanFlowView() }
        .sheet(isPresented: $showingEditor) {
            MarkerEditorView { drafts in await save(drafts) }
        }
        .sheet(item: Binding(get: { detailKey.flatMap { key in allMarkers.first { $0.key == key } } },
                             set: { detailKey = $0?.key })) { marker in
            MarkerDetailView(markerKey: marker.key, readings: marker.readings, title: marker.name,
                             chart: AnyView(BiologyHistoryChart(marker: marker)),
                             onDelete: { id in await delete(id) })
        }
    }

    private func load() async {
        guard var all = await LabBookView.loadAll(repo) else { return }
        if await LabScanRekey.run(all, repo: repo), let reloaded = await LabBookView.loadAll(repo) { all = reloaded }
        let rows = all.filter { !Self.excluded.contains($0.category) }
        // Every strap sync bumps refreshSeq; rebuilding identical cards then is a visible hitch.
        guard !loaded || rows != loadedRows else { return }
        loadedRows = rows
        reportDays = Array(Set(rows.map(\.day))).sorted(by: >)
        if let d = selectedDay, !reportDays.contains(d) { selectedDay = nil }
        allMarkers = BiologyMarker.build(rows, sex: AICoachEngine.profileSex)
        rebuild()
        loaded = true
    }

    /// The cards for the selected report: each marker as it stood on that day (its history up to then), and
    /// only the markers measured that day. "Latest results" shows every marker's latest reading.
    private func rebuild() {
        let shown: [BiologyMarker]
        if let day = selectedDay {
            shown = BiologyMarker.build(loadedRows.filter { $0.day <= day }, sex: AICoachEngine.profileSex)
                .filter { $0.latest?.day == day }
        } else {
            shown = allMarkers
        }
        let byGroup = Dictionary(grouping: shown, by: \.group)
        groups = BiologyGroup.allCases.compactMap { g in byGroup[g].map { (g, $0) } }
        markers = shown
    }

    private var reportPicker: some View {
        Menu {
            Button("Latest results") { selectedDay = nil; rebuild() }
            Divider()
            ForEach(reportDays, id: \.self) { d in
                Button("Report of \(LabBookFormat.dayFromKey(d))") { selectedDay = d; rebuild() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(selectedDay.map { "Report of \(LabBookFormat.dayFromKey($0))" } ?? String(localized: "Latest results"))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(StrandFont.subhead.weight(.semibold))
            .foregroundStyle(StrandPalette.accent)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(StrandPalette.surfaceRaised))
        }
        .accessibilityLabel("Choose a lab report")
    }

    private func save(_ drafts: [LabMarkerRow]) async {
        guard !drafts.isEmpty, let store = await repo.storeHandle() else { return }
        try? await store.upsertLabMarkers(drafts)
        await repo.refresh()
        await load()
    }

    private func delete(_ id: String) async {
        guard let store = await repo.storeHandle() else { return }
        _ = try? await store.deleteLabMarker(id: id)
        await repo.refresh()
        await load()
    }
}

/// The Biology header: how many markers sit inside / outside their report ranges, the last test date, and
/// the two ways in (scan a report, add by hand).
struct BiologySummaryCard: View {
    let markers: [BiologyMarker]
    let onScan: () -> Void
    let onAdd: () -> Void

    private var inRange: Int { markers.filter { $0.status == .inRange }.count }
    private var outOfRange: Int { markers.filter { $0.status == .below || $0.status == .above }.count }
    private var lastDay: String? { markers.compactMap { $0.latest?.day }.max() }

    var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    count(inRange, "In range", HealthMonitorSection.inRangeColor)
                    count(outOfRange, "Out of range", HealthMonitorSection.outOfRangeColor)
                    count(markers.count, "Markers", StrandPalette.textPrimary)
                }
                if let lastDay {
                    Text("Last results \(LabBookFormat.dayFromKey(lastDay))")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
                HStack(spacing: 10) {
                    NoopButton("Scan lab report", systemImage: "doc.text.viewfinder", kind: .primary, fullWidth: true, action: onScan)
                    NoopButton("Add", systemImage: "plus", kind: .secondary, action: onAdd)
                }
            }
        }
    }

    private func count(_ n: Int, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(StrandFont.rounded(28)).foregroundStyle(color)
            Text(label).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
