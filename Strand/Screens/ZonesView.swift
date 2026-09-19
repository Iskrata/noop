import SwiftUI
import StrandDesign
import StrandAnalytics

/// Live heart rate and the zone it sits in, big enough to read mid-exercise (a stair climber, a bike). Uses the
/// profile's zone set, the same one workout zone coaching uses, and keeps the screen awake while it is showing.
struct ZonesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.scenePhase) private var scenePhase
    /// Whether this screen holds one of the realtime-HR claims (`AppModel.startRealtimeHR`), so every start is
    /// balanced by exactly one stop.
    @State private var holdsRealtime = false
    @State private var visible = false
    /// Fork: the stream starts only when the user taps Start (it used to arm on every visit); leaving the tab
    /// or backgrounding the app still releases it, and a return shows Start again.
    @State private var running = false

    private var zoneSet: HRZoneSet { model.profile.hrZoneSet }
    private var zone: Int { model.bpm.map { zoneSet.zoneNumber(forBPM: Double($0)) } ?? 0 }
    private var tint: Color { zone >= 1 ? StrandPalette.hrZoneColor(zone) : StrandPalette.textSecondary }

    var body: some View {
        ScreenScaffold(title: "Zones", subtitle: "Live heart rate", topBackground: liquidScaffoldSky()) {
            NoopCard {
                VStack(spacing: NoopMetrics.space1) {
                    Text(model.bpm.map(String.init) ?? "--")
                        .font(StrandFont.number(120))
                        .foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: model.bpm)
                    Text(live.bonded ? String(localized: "bpm") : String(localized: "Strap not connected"))
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            NoopButton(running ? "Stop" : "Start live heart rate", systemImage: running ? "stop.fill" : "play.fill",
                       kind: running ? .secondary : .primary, fullWidth: true) {
                running.toggle()
                setRealtime(running && visible && scenePhase == .active)
            }
            NoopCard { HRZoneSection(zone: zone, zoneSet: zoneSet) }
            NoopCard {
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text("Your zones").strandOverline()
                    ForEach(zoneSet.zones, id: \.number) { band in
                        HStack {
                            Circle().fill(StrandPalette.hrZoneColor(band.number)).frame(width: 10, height: 10)
                            Text("Z\(band.number) · \(HRZoneSection.name(band.number))")
                                .font(StrandFont.body)
                                .foregroundStyle(band.number == zone ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                            Spacer()
                            Text("\(Int(band.lower))-\(Int(band.upper)) bpm")
                                .font(StrandFont.bodyNumber)
                                .foregroundStyle(band.number == zone ? StrandPalette.hrZoneColor(band.number) : StrandPalette.textTertiary)
                        }
                    }
                    Text("Max HR \(Int(zoneSet.maxHR)) bpm. Change it in Settings.")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        // The strap only streams per-second heart rate while a screen asks for it; without this the big number
        // stayed "--" and no zone lit. Released when the tab is left or the app goes to the background (a
        // background transition fires no onDisappear), so the stream never runs unseen.
        .onAppear { visible = true }
        .onDisappear { visible = false; running = false; setRealtime(false) }
        // A tab that is not showing stays alive in the TabView and still sees scene changes, hence `visible`.
        .onChangeCompat(of: scenePhase == .active) { active in setRealtime(active && visible && running) }
        .onChangeCompat(of: live.bonded) { _ in model.rearmRealtimeIfWanted() }
        .onChangeCompat(of: live.connected) { _ in model.rearmRealtimeIfWanted() }
    }

    private func setRealtime(_ wanted: Bool) {
        guard wanted != holdsRealtime else { return }
        holdsRealtime = wanted
        if wanted { model.startRealtimeHR() } else { model.stopRealtimeHR() }
        ScreenIdle.keepAwake(wanted)
    }
}
