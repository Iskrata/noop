import SwiftUI
import StrandDesign

// MARK: - Bevel-style Today header (fork)
//
// Bevel's top of Home: a status pill that pulses while the strap syncs and briefly says "Sync complete"
// afterwards, the profile picture on the right, and the strap battery as Bevel's Energy bar (a row of
// ticks with the percentage) instead of the round charge/sync button.

/// Pulsing sync pill. Hidden while idle; pulses with the chunk count while an offload runs; shows "Sync
/// complete" for a few seconds once it ends.
struct SyncStatusPill: View {
    @EnvironmentObject private var live: LiveState
    @State private var syncing = false
    @State private var justFinished = false
    @State private var pulse = false

    var body: some View {
        Group {
            if syncing {
                pill(icon: "arrow.triangle.2.circlepath", tint: StrandPalette.metricCyan,
                     text: live.syncChunksThisSession > 0
                        ? String(localized: "Syncing · \(live.syncChunksThisSession)")
                        : String(localized: "Syncing…"))
                    .opacity(pulse ? 0.55 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                    }
                    .onDisappear { pulse = false }
            } else if justFinished {
                pill(icon: "checkmark.circle.fill", tint: StrandPalette.chargeColor,
                     text: String(localized: "Sync complete"))
                    .transition(.opacity)
            }
        }
        .debouncedSyncSignal(live.backfilling, into: $syncing)
        .onChangeCompat(of: syncing) { now in
            guard !now else { justFinished = false; return }
            withAnimation { justFinished = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { justFinished = false }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pill(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
            Text(text).font(StrandFont.number(16)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(tint.opacity(0.18))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)))
    }
}

/// Bevel's Energy bar mapped to the strap battery: a bolt, a row of ticks filled to the charge, and the
/// percentage. Tapping opens Devices. Not drawn when the strap isn't the active device.
struct StrapEnergyBar: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    let cardOpacity: Double

    private static let ticks = 36

    var body: some View {
        let display = LiquidTodayView.StrapBatteryDisplay.resolve(
            activeIsWhoop: live.activeIsWhoop, connected: live.connected,
            batteryPct: live.batteryPct, charging: live.charging)
        if case .notActiveDevice = display {
            EmptyView()
        } else {
            let (pct, charging): (Double?, Bool) = {
                switch display {
                case .charge(let p, let c): return (p, c)
                case .pending(let c): return (nil, c)
                default: return (nil, false)
                }
            }()
            Button { router.openDevices() } label: {
                HStack(spacing: 12) {
                    Image(systemName: charging ? "bolt.fill" : "bolt")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Self.tint(pct))
                    ticks(pct)
                    Text(pct.map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(StrandFont.rounded(22)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 58, alignment: .trailing)
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(NoopPanelSurface(cornerRadius: 22, surfaceOpacity: cardOpacity))
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityLabel(pct.map { String(localized: "Strap battery \(Int($0.rounded())) percent") }
                                ?? String(localized: "Strap battery unknown"))
        }
    }

    private func ticks(_ pct: Double?) -> some View {
        let filled = Int(((pct ?? 0) / 100 * Double(Self.ticks)).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<Self.ticks, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Self.tint(pct) : StrandPalette.textTertiary.opacity(0.25))
                    .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Green above 40 %, amber down to 15 %, red below — the strap's low-battery alert fires at 15 %.
    static func tint(_ pct: Double?) -> Color {
        guard let pct else { return StrandPalette.textTertiary }
        if pct > 40 { return Color(hex: "#5BD64B") }
        if pct > 15 { return Color(hex: "#F2C94C") }
        return Color(hex: "#EB5757")
    }
}
