import SwiftUI
import StrandDesign

/// Fork: a card of Coach tips (lab report / sleep week). `load` returns the tips — the engine serves them from
/// its once-only cache, so the card can ask on every appear; nil (Coach off, no consent, request failed) hides
/// the card. `id` re-runs the load when the subject changes (another report, a new night).
struct CoachTipsCard: View {
    let title: LocalizedStringKey
    let id: String
    let load: () async -> [String]?

    @State private var tips: [String]?
    @State private var loading = false

    var body: some View {
        // A VStack, not a Group: an empty Group has no view to appear, so its `.task` never ran and the card
        // never loaded (the first build showed nothing on either screen). The stack exists even when empty.
        VStack(spacing: 0) {
            if loading || tips?.isEmpty == false {
                NoopCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(title, systemImage: "sparkles")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                        if let tips, !tips.isEmpty {
                            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle().fill(StrandPalette.accent).frame(width: 5, height: 5)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                                    Text(tip).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(StrandPalette.accent)
                                Text("Coach is reading your numbers…")
                                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: id) {
            tips = nil
            loading = true
            tips = await load()
            loading = false
            NSLog("Coach: tips card %@ -> %d tip(s)", id, tips?.count ?? -1)
        }
    }
}
