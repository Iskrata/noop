import SwiftUI
import StrandDesign

/// Fork: Lab → Heart & Breathing — the irregular-rhythm and breathing-disturbance screens' current state,
/// each opening its history (`HeartBreathingDetailView`).
struct HeartBreathingSection: View {
    @EnvironmentObject var repo: Repository
    @State private var detail: HeartBreathingDetailView.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Heart & Breathing", overline: "Screening from your strap")
            ForEach([HeartBreathingDetailView.Kind.rhythm, .breathing]) { kind in
                Button { detail = kind } label: {
                    NoopCard {
                        HStack {
                            HeartBreathingSummary(kind: kind)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                }
                .buttonStyle(LiquidPressStyle())
            }
        }
        .task(id: repo.refreshSeq) { await HeartBreathingStore.shared.loadIfNeeded(repo: repo) }
        .sheet(item: $detail) { HeartBreathingDetailView(kind: $0) }
    }
}
