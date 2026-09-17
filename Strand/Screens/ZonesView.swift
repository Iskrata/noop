import SwiftUI
import StrandDesign
import StrandAnalytics

/// Live heart rate and the zone it sits in, big enough to read mid-exercise (a stair climber, a bike). Uses the
/// profile's zone set, the same one workout zone coaching uses, and keeps the screen awake while it is showing.
struct ZonesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

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
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }
}
