import SwiftUI
import StrandDesign

// MARK: - Bevel-style Today header (fork)
//
// Bevel's top of Home: a hairline sync bar along the top edge, the profile picture on the right, and the strap battery as Bevel's Energy bar (a row of
// ticks with the percentage) instead of the round charge/sync button.

/// A hairline across the top of Today while the strap syncs: a faint track with a light sweeping left to
/// right, fading out when the offload ends. Replaces the "Syncing" pill, which drew a large chip for what is
/// usually an eight-second top-up. Reduce Motion / Low Power Mode show the track without the sweep.
struct SyncProgressBar: View {
    @EnvironmentObject private var live: LiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var syncing = false
    @State private var phase: CGFloat = 0

    private static let height: CGFloat = 2.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.accent.opacity(0.18))
                if !motion.poseStill(reduceMotion) {
                    Capsule()
                        .fill(LinearGradient(colors: [StrandPalette.accent.opacity(0), StrandPalette.accent,
                                                      StrandPalette.accent.opacity(0)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.35)
                        .offset(x: -w * 0.35 + phase * w * 1.35)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: Self.height)
        .opacity(syncing ? 1 : 0)
        .animation(.easeInOut(duration: 0.35), value: syncing)
        .debouncedSyncSignal(live.backfilling, into: $syncing)
        .onChangeCompat(of: syncing) { sweep($0) }
        .onAppear { sweep(syncing) }
        .onDisappear { phase = 0 }
        .accessibilityElement()
        .accessibilityLabel(syncing ? String(localized: "Syncing") : "")
        .accessibilityHidden(!syncing)
    }

    private func sweep(_ on: Bool) {
        guard on, !motion.poseStill(reduceMotion) else { phase = 0; return }
        phase = 0
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
    }
}

/// Bevel's Energy bar mapped to the strap battery: a bolt, a row of ticks filled to the charge, and the
/// percentage. Tapping opens Devices. Not drawn when the strap isn't the active device.
struct StrapEnergyBar: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reduce-motion and Low Power Mode hold the bar still instead of pulsing.
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var pulse = false
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
            // Pulses while the strap charges or the link is still coming up (no reading yet / offline).
            let busy: Bool = {
                switch display {
                case .charge(_, let c): return c
                default: return true
                }
            }()
            Button { router.openDevices() } label: {
                HStack(spacing: 10) {
                    Image(systemName: charging ? "bolt.fill" : "bolt")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Self.tint(pct))
                    ticks(pct)
                        .opacity(busy && pulse ? 0.45 : 1)
                    Text(pct.map { "\(Int($0.rounded()))%" } ?? "–")
                        .font(StrandFont.rounded(14)).monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(NoopPanelSurface(cornerRadius: 12, surfaceOpacity: cardOpacity))
            }
            .buttonStyle(LiquidPressStyle())
            .onAppear { startPulse(busy) }
            .onChangeCompat(of: busy) { startPulse($0) }
            .accessibilityLabel(pct.map { String(localized: "Strap battery \(Int($0.rounded())) percent") }
                                ?? String(localized: "Strap battery unknown"))
        }
    }

    private func startPulse(_ busy: Bool) {
        guard busy, !motion.poseStill(reduceMotion) else {
            withAnimation(.default) { pulse = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
    }

    private func ticks(_ pct: Double?) -> some View {
        let filled = Int(((pct ?? 0) / 100 * Double(Self.ticks)).rounded())
        return HStack(spacing: 2) {
            ForEach(0..<Self.ticks, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Self.tint(pct) : StrandPalette.textTertiary.opacity(0.25))
                    .frame(height: 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The status trio: green above 40 %, amber down to 15 %, red below — the strap's low-battery alert
    /// fires at 15 %.
    static func tint(_ pct: Double?) -> Color {
        guard let pct else { return StrandPalette.textTertiary }
        if pct > 40 { return StrandPalette.statusPositive }
        if pct > 15 { return StrandPalette.statusWarning }
        return StrandPalette.statusCritical
    }
}
