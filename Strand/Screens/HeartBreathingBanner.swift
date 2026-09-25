import SwiftUI
import StrandAnalytics
import StrandDesign

/// Fork: the Today banner for a REPEATING irregular-rhythm or breathing-disturbance pattern
/// (`HeartBreathingPatterns`). A single episode or night stays in Lab. Dismissing hides that pattern until a
/// new episode day or elevated night arrives. Tapping opens the history.
struct HeartBreathingBanner: View {
    @ObservedObject private var hb = HeartBreathingStore.shared
    @AppStorage("fork.heartBreathing.dismissedBanners") private var dismissedCSV = ""
    @State private var detail: HeartBreathingDetailView.Kind?

    private struct Item: Identifiable {
        let kind: HeartBreathingDetailView.Kind
        /// Changes when the pattern gets a new day, so a dismissal only silences what the user has seen.
        let signature: String
        let text: String
        var id: String { signature }
    }

    private var items: [Item] {
        var out: [Item] = []
        let r = hb.rhythmPattern
        if r.repeating, let last = r.daysWithEpisodes.last {
            out.append(Item(kind: .rhythm, signature: "rhythm:\(last)",
                            text: "Irregular heart rhythm on \(r.daysWithEpisodes.count) days in the last 2 weeks, a pattern that can point to atrial fibrillation. Screening estimate from your strap, not a diagnosis; worth showing a doctor."))
        }
        let b = hb.breathingPattern
        if b.repeating, let last = hb.breathing.filter({ $0.value.index >= CvhrDetector.elevatedIndex }).keys.max() {
            out.append(Item(kind: .breathing, signature: "breathing:\(last)",
                            text: "Breathing disturbances were elevated on \(b.elevatedNights) of your last \(b.readableNights) nights, a pattern seen with sleep apnea. Screening estimate, not a diagnosis; worth mentioning to a doctor."))
        }
        let dismissed = Set(dismissedCSV.split(separator: ",").map(String.init))
        return out.filter { !dismissed.contains($0.signature) }
    }

    var body: some View {
        let shown = items
        if !shown.isEmpty {
            VStack(spacing: 12) {
                ForEach(shown) { item in card(item) }
            }
            .sheet(item: $detail) { HeartBreathingDetailView(kind: $0) }
        }
    }

    private func card(_ item: Item) -> some View {
        NoopCard(padding: 14, tint: StrandPalette.statusWarning) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.statusWarning)
                    .frame(width: 30, height: 30)
                    .background(StrandPalette.statusWarning.opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                Text(item.text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    dismissedCSV = (dismissedCSV.split(separator: ",").map(String.init) + [item.signature]).joined(separator: ",")
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { detail = item.kind }
        .accessibilityAddTraits(.isButton)
    }
}
