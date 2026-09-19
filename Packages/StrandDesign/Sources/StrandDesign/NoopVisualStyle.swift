import SwiftUI

// MARK: - NOOP visual foundation
//
// These tokens describe the visual treatment used by NOOP's existing views. They deliberately
// contain no navigation, state, or domain semantics: screens keep their current hierarchy and data
// bindings, while cards, gauges, typography, and chrome share one maintainable source of truth.

public enum NoopVisualStyle {
    // Neutral, low-chroma surfaces. DARK re-anchored 2026-09-17 on WHOOP's own official "Background
    // Gradient" (#283339 → #101518, from the same sourced Brand & Design Guidelines PDF cited above
    // `StrandPalette.whoopStrain`) so this fork's dark mode reads near-black like WHOOP's, not the
    // previous dark-navy-grey. `canvas` takes the darker stop, `surface` the lighter one (WHOOP's own
    // background gradient describes screen depth, not cards, but the two stops map cleanly onto NOOP's
    // base/card split). `surfaceTop`/`surfaceBottom`/`inset`/`border`/`borderHighlight`/`divider` keep
    // the SAME relative offsets from `surface` that the previous values had, so the existing top-lit
    // card gradient and hairline contrast survive the re-anchor unchanged — only the base tone moved.
    // LIGHT is untouched (WHOOP ships dark-only, so there is nothing WHOOP-sourced to move it to).
    //
    // 2026-09-19: moved again, to WHOOP's app itself. The guideline gradient above is blue-grey, so the
    // screens still read navy. WHOOP's app draws on its brand Black #000000 (the same guidelines PDF) with
    // neutral, hue-free dark-grey cards, so DARK is now pure black + neutral greys at the same relative
    // steps (surface/top/bottom/inset/border/highlight/divider) as before.
    public static let canvas = Color(light: "#F3F4F6", dark: "#000000")
    public static let surface = Color(light: "#FFFFFF", dark: "#1A1A1A")
    public static let surfaceTop = Color(light: "#FFFFFF", dark: "#202020")
    public static let surfaceBottom = Color(light: "#F4F5F7", dark: "#161616")
    public static let inset = Color(light: "#E8E9ED", dark: "#0E0E0E")

    public static let border = Color(light: "#D8DAE0", dark: "#262626")
    public static let borderHighlight = Color(light: "#FFFFFF", dark: "#3A3A3A")
    public static let divider = Color(light: "#E4E5E9", dark: "#282828")

    public static let primaryText = Color(light: "#17181C", dark: "#FFFFFF") // WHOOP WHITE #FFFFFF (sourced)
    public static let secondaryText = Color(light: "#555861", dark: "#C3C4CA")
    public static let tertiaryText = Color(light: "#7D808A", dark: "#7D7F88")

    public static let mint = Color(light: "#149A78", dark: "#69DDB8")
    public static let mintDeep = Color(light: "#0D765C", dark: "#13A982")
    public static let mintGlow = Color(light: "#38C99E", dark: "#54E6BD")

    public static let cardRadius: CGFloat = 22
    public static let compactRadius: CGFloat = 16
    public static let pillRadius: CGFloat = 999
    public static let pagePadding: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let sectionGap: CGFloat = 26
}

/// Shared card/panel treatment: a quiet vertical gradient, a top-lit rim, and deep soft elevation.
/// `tint` is intentionally faint so metric identity never turns the whole card into a coloured tile.
public struct NoopPanelSurface: View {
    public var tint: Color?
    public var cornerRadius: CGFloat
    public var elevated: Bool
    public var surfaceOpacity: Double
    @Environment(\.colorScheme) private var scheme

    public init(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.surfaceOpacity = surfaceOpacity
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                if let tint {
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(0.055), tint.opacity(0.012), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [NoopVisualStyle.borderHighlight.opacity(0.72), NoopVisualStyle.border.opacity(0.52)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            )
            .shadow(
                color: scheme == .dark ? .black.opacity(elevated ? 0.34 : 0.18) : .black.opacity(0.10),
                radius: elevated ? 18 : 9,
                x: 0,
                y: elevated ? 10 : 5
            )
            .opacity(surfaceOpacity)
    }
}

/// Shared edge-to-edge chrome for sheet and split-view headers. Unlike a card it has no
/// rounded outline or elevation, but it uses the same top-lit surface ramp and divider token.
public struct NoopChromeSurface: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            colors: [NoopVisualStyle.surfaceTop, NoopVisualStyle.surfaceBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoopVisualStyle.divider)
                .frame(height: 0.5)
        }
    }
}

public extension View {
    func noopPanel(
        tint: Color? = nil,
        cornerRadius: CGFloat = NoopVisualStyle.cardRadius,
        elevated: Bool = false,
        surfaceOpacity: Double = 1
    ) -> some View {
        background {
            NoopPanelSurface(
                tint: tint,
                cornerRadius: cornerRadius,
                elevated: elevated,
                surfaceOpacity: surfaceOpacity
            )
        }
    }
}
