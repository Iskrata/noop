import SwiftUI
import StrandDesign

/// Fork: one report page exactly as it will be uploaded — blanked lines drawn solid black. Every text line
/// the on-device OCR found is tappable: tap to blank it, tap a black box to reveal it again.
struct LabRedactionPreview: View {
    @Binding var page: LabScanPage

    var body: some View {
        let size = page.image.size
        Image(uiImage: page.image)
            .resizable()
            .aspectRatio(size, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let scale = geo.size.width / max(size.width, 1)
                    ForEach(page.lines.indices, id: \.self) { i in
                        let r = LabScanImages.rect(page.lines[i], in: size)
                        let blanked = page.redacted.contains(i)
                        Rectangle()
                            .fill(blanked ? Color.black : StrandPalette.accent.opacity(0.08))
                            .overlay(Rectangle().stroke(blanked ? Color.clear : StrandPalette.accent.opacity(0.35),
                                                        lineWidth: 0.5))
                            .frame(width: r.width * scale, height: r.height * scale)
                            .position(x: r.midX * scale, y: r.midY * scale)
                            .onTapGesture { toggle(i) }
                            .accessibilityLabel(blanked ? Text("Hidden line") : Text(page.lines[i].text))
                            .accessibilityHint(blanked ? Text("Double tap to show") : Text("Double tap to hide"))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggle(_ i: Int) {
        if page.redacted.contains(i) { page.redacted.remove(i) } else { page.redacted.insert(i) }
    }
}
