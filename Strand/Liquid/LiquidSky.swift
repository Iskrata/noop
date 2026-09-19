//  LiquidSky.swift
//  NOOP · Liquid design language
//
//  The time-of-day sky: a gradient that flows continuously through the day's
//  keyframes, a quiet starfield, and two subtle sheets of light. No objects,
//  no blur — clean and crisp, the atmosphere of the app's header.

import SwiftUI
import StrandDesign

struct LiquidSkyStop {
    let h: Double
    let top: Color, mid: Color, hor: Color
    let stars: Double, warm: Double
}

private func hx(_ hex: UInt32) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xff) / 255,
          green: Double((hex >> 8) & 0xff) / 255,
          blue: Double(hex & 0xff) / 255, opacity: 1)
}

/// The ten keyframes mirror the real app's day-cycle scenes (SceneHeroBackground),
/// as pure gradients rather than painted art.
let liquidSkyKeys: [LiquidSkyStop] = [
    .init(h: 0,    top: hx(0x191A1F), mid: hx(0x1D1E23), hor: hx(0x22242B), stars: 0.20, warm: 0),
    .init(h: 5,    top: hx(0x1A1B20), mid: hx(0x1D1F24), hor: hx(0x23252C), stars: 0.12, warm: 0),
    .init(h: 6.5,  top: hx(0x1B1C21), mid: hx(0x1F2026), hor: hx(0x25272E), stars: 0.06, warm: 0),
    .init(h: 8.5,  top: hx(0x1C1D22), mid: hx(0x202229), hor: hx(0x272A31), stars: 0, warm: 0),
    .init(h: 11,   top: hx(0x1D1E23), mid: hx(0x21232A), hor: hx(0x292C33), stars: 0, warm: 0),
    .init(h: 14,   top: hx(0x1D1E23), mid: hx(0x22242B), hor: hx(0x292C34), stars: 0, warm: 0),
    .init(h: 17.5, top: hx(0x1C1D22), mid: hx(0x202229), hor: hx(0x272930), stars: 0, warm: 0),
    .init(h: 19.5, top: hx(0x1B1C21), mid: hx(0x1F2026), hor: hx(0x24262D), stars: 0.05, warm: 0),
    .init(h: 22,   top: hx(0x191A1F), mid: hx(0x1D1E23), hor: hx(0x22242B), stars: 0.16, warm: 0),
    .init(h: 24,   top: hx(0x191A1F), mid: hx(0x1D1E23), hor: hx(0x22242B), stars: 0.20, warm: 0),
]

/// Light appearance keeps the same time-of-day movement without beginning from the dark-only
/// keyframes above. The restrained blue-gray atmosphere settles naturally into the light canvas.
private let liquidLightSkyKeys: [LiquidSkyStop] = [
    .init(h: 0,    top: hx(0xDCE3ED), mid: hx(0xE5EAF1), hor: hx(0xEEF1F5), stars: 0.08, warm: 0),
    .init(h: 5,    top: hx(0xDDE5EE), mid: hx(0xE7EBF1), hor: hx(0xEFF2F5), stars: 0.05, warm: 0),
    .init(h: 6.5,  top: hx(0xE1E8EF), mid: hx(0xE9EDF2), hor: hx(0xF0F2F5), stars: 0.02, warm: 0),
    .init(h: 8.5,  top: hx(0xE3EBF1), mid: hx(0xEAF0F3), hor: hx(0xF1F3F5), stars: 0, warm: 0),
    .init(h: 11,   top: hx(0xE1EAF0), mid: hx(0xE9EEF2), hor: hx(0xF1F3F5), stars: 0, warm: 0),
    .init(h: 14,   top: hx(0xDFE8EF), mid: hx(0xE8EDF2), hor: hx(0xF0F2F5), stars: 0, warm: 0),
    .init(h: 17.5, top: hx(0xE1E7ED), mid: hx(0xE8ECF1), hor: hx(0xEFF1F4), stars: 0, warm: 0),
    .init(h: 19.5, top: hx(0xDDE4EC), mid: hx(0xE6EAF0), hor: hx(0xEEF1F4), stars: 0.02, warm: 0),
    .init(h: 22,   top: hx(0xDAE2EC), mid: hx(0xE4E9F0), hor: hx(0xEDF0F4), stars: 0.06, warm: 0),
    .init(h: 24,   top: hx(0xDCE3ED), mid: hx(0xE5EAF1), hor: hx(0xEEF1F5), stars: 0.08, warm: 0),
]

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func lerpColor(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let x = a.liquidComponents(), y = b.liquidComponents()
    return Color(.sRGB, red: lerp(x.r, y.r, t), green: lerp(x.g, y.g, t), blue: lerp(x.b, y.b, t), opacity: 1)
}

func liquidSkyAt(_ hour: Double, light: Bool = false) -> (top: Color, mid: Color, hor: Color, stars: Double, warm: Double) {
    let keys = light ? liquidLightSkyKeys : liquidSkyKeys
    var i = 0
    while i < keys.count - 2 && keys[i + 1].h <= hour { i += 1 }
    let a = keys[i], b = keys[i + 1]
    let t = max(0, min(1, (hour - a.h) / (b.h - a.h)))
    return (lerpColor(a.top, b.top, t), lerpColor(a.mid, b.mid, t), lerpColor(a.hor, b.hor, t),
            lerp(a.stars, b.stars, t), lerp(a.warm, b.warm, t))
}

/// A precomputed quiet star field (positions fixed; only the count that render
/// depends on how starry the hour is).
private struct LiquidStar { let x, y, z, ph, sp: Double }
private let liquidStars: [LiquidStar] = (0..<70).map { _ in
    LiquidStar(x: .random(in: 0...1), y: .random(in: 0...0.78), z: .random(in: 0...1),
               ph: .random(in: 0..<7), sp: 0.2 + .random(in: 0..<0.5))
}

/// The sky's paint, one function per layer, shared by the live `LiquidSky` and `LiquidSkyStatic` so the
/// two can never draw a different picture. Each layer is a single fill, and the layers are always
/// composited in this order: base → breath → warm → stars → settle.
enum LiquidSkyPaint {
    /// The theme's canvas colour (`surfaceBase`) the sky dissolves into, so there is no hard seam where
    /// the sky meets the page — light mode made this glaring.
    static func settleColor(dark: Bool) -> Color {
        Color(.sRGB,
              red: dark ? 29.0 / 255.0 : 242.0 / 255.0,
              green: dark ? 30.0 / 255.0 : 242.0 / 255.0,
              blue: dark ? 35.0 / 255.0 : 247.0 / 255.0,
              opacity: 1)
    }

    /// The gradient IS the scene.
    static func base(_ ctx: GraphicsContext, _ size: CGSize, top: Color, mid: Color, hor: Color) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: top, location: 0),
                    .init(color: mid, location: 0.5),
                    .init(color: hor, location: 0.9)]),
                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// The slow breath of light low in the sky, at FULL strength (end stop opacity 1). The live sky
    /// scales the whole layer with `.opacity(0.05 + breathe * 0.03)`; gradient alpha is linear in the
    /// stop, so that is the same pixel as painting the end stop at that opacity directly.
    static func breath(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0), .white]),
                                       startPoint: CGPoint(x: 0, y: h * 0.45), endPoint: CGPoint(x: 0, y: h)))
    }

    static func warm(_ ctx: GraphicsContext, _ size: CGSize, amount: Double) {
        let w = size.width, h = size.height
        let warm = Color(.sRGB, red: 1, green: 200/255, blue: 120/255, opacity: 1)
        ctx.fill(Path(CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45)),
                 with: .linearGradient(Gradient(colors: [warm.opacity(0), warm.opacity(amount * 0.10)]),
                                       startPoint: CGPoint(x: 0, y: h * 0.55), endPoint: CGPoint(x: 0, y: h)))
    }

    /// The star field. `now` nil poses every star at its resting brightness (no twinkle).
    static func stars(_ ctx: GraphicsContext, _ size: CGSize, amount: Double, now: Double?) {
        let w = size.width, h = size.height
        for s in liquidStars {
            let baseA = 0.04 + s.z * 0.16
            let tw = now.map { pow(max(0, sin(s.ph + $0 * s.sp)), 6) } ?? 0
            let o = amount * (baseA + tw * 0.28)
            if o < 0.02 { continue }
            let sz = 0.6 + s.z * 0.8
            ctx.fill(Path(CGRect(x: s.x * w, y: s.y * h, width: sz, height: sz)), with: .color(.white.opacity(o)))
        }
    }

    /// Settle into the page: a long fade to the theme's surfaceBase over the lower half so the sky
    /// dissolves seamlessly into the body — no hard cut (the light-mode dark→white slam is gone).
    static func settle(_ ctx: GraphicsContext, _ size: CGSize, color: Color, strength: Double) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
                 with: .linearGradient(Gradient(colors: [color.opacity(0), color.opacity(strength)]),
                                       startPoint: CGPoint(x: 0, y: h * 0.45), endPoint: CGPoint(x: 0, y: h)))
    }

    static func liveHour(_ date: Date = Date()) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }
}

struct LiquidSky: View {
    /// Hour of day 0...24. Defaults to live time when nil.
    var hour: Double?
    /// How fully the sky dissolves into the canvas at the bottom (1 = the default seamless fade; <1 holds
    /// the atmosphere so the sky still reads under a full-height "sky behind cards" backdrop).
    var settleStrength: Double = 1
    @Environment(\.colorScheme) private var scheme
    /// The call site already swaps in `LiquidSkyStatic` when motion is unwanted, but this view carried
    /// no gate of its own — a second call site would have been silently ungated. `paused:` makes the
    /// frame loop stand down from inside, so the gate travels with the view.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    /// The breath's clock. Its opacity swings by 0.03 over a ~28.6 s period (`sin(now * 0.22)`), so it
    /// moves at most 0.03 × 0.5 × 0.22 ≈ 0.0033 alpha per second: one 2 fps step is under half of one
    /// 8-bit level (1/255 ≈ 0.0039). Ticking it at the stars' 20 fps repainted pixels that could not
    /// change; 2 fps is the same picture.
    private static let breathInterval = 1.0 / 2.0
    /// The twinkle's clock, unchanged from the single-canvas sky.
    private static let starsInterval = 1.0 / 20.0

    // PERF: the scene is stacked layers, composited in the exact order the old single Canvas filled
    // them, so the picture is the same. Only the two layers that move sit under a clock. Repainting the
    // whole sky 20 times a second (four full-screen gradients) cost about as much main-thread time as the
    // 60 fps heart-rate thread, for a daytime change of three hundredths of opacity. Now the static layers
    // paint once a minute, the breath re-composites a cached layer by opacity, and the stars (absent by
    // day: no daytime keyframe carries any) keep their 20 fps twinkle and render off the main thread.
    // Mac harness, full-window sky over the real store: by day ~9% of a main-thread core → under 1%;
    // at night unchanged (~9%).
    var body: some View {
        // The live hour moves once a minute, so the layers that depend on it repaint once a minute.
        TimelineView(.everyMinute) { _ in
            let dark = scheme == .dark
            let S = liquidSkyAt(hour ?? LiquidSkyPaint.liveHour(), light: !dark)
            let settle = LiquidSkyPaint.settleColor(dark: dark)
            let paused = motion.poseStill(reduceMotion)
            ZStack {
                Canvas { ctx, size in LiquidSkyPaint.base(ctx, size, top: S.top, mid: S.mid, hor: S.hor) }
                TimelineView(.animation(minimumInterval: Self.breathInterval, paused: paused)) { tl in
                    let breathe = 0.5 + 0.5 * sin(liquidSeconds(tl.date) * 0.22)
                    LiquidSkyBreathLayer().opacity(0.05 + breathe * 0.03)
                }
                if S.warm > 0.01 {
                    Canvas { ctx, size in LiquidSkyPaint.warm(ctx, size, amount: S.warm) }
                }
                if S.stars > 0.01 {
                    TimelineView(.animation(minimumInterval: Self.starsInterval, paused: paused)) { tl in
                        let now = liquidSeconds(tl.date)
                        // Pure over its captured values, so it can render off the main thread.
                        Canvas(rendersAsynchronously: true) { ctx, size in
                            LiquidSkyPaint.stars(ctx, size, amount: S.stars, now: now)
                        }
                    }
                }
                Canvas { ctx, size in
                    LiquidSkyPaint.settle(ctx, size, color: settle, strength: settleStrength)
                }
            }
        }
    }
}

/// The breath sheet at full strength. A separate view with no inputs, so the clock above it changes only
/// its opacity and never re-runs this paint.
private struct LiquidSkyBreathLayer: View {
    var body: some View {
        Canvas { ctx, size in LiquidSkyPaint.breath(ctx, size) }
    }
}

/// A subtle full-bleed time-of-day sky for any `ScreenScaffold.topBackground`, so the liquid
/// atmosphere carries across EVERY tab. Same live sky as Today at a modest header height, so the
/// charts/cards below sit on the dark canvas — the redesign's "the options change, not the page"
/// feel. Non-interactive + accessibility-hidden (pure decoration).
///
/// Honours the SAME two Appearance gates as Today and the metric-detail screens, so every scaffold
/// that passes this reads them for free (Trends / Sleep / More / the hub screens previously ignored
/// both — the sky stayed a fixed band there while Today filled the viewport):
/// - "Day-cycle background" OFF renders nothing, leaving the scaffold's plain `surfaceBase` canvas
///   (the same visual as passing no topBackground at all).
/// - "Sky behind cards" ON fills the scaffold's whole backdrop (the ZStack already spans the scroll
///   view; only this frame capped it) with the held-atmosphere settle, so the Card-transparency
///   setting reveals the sky under every card — the LiquidTodayView treatment.
/// A real View (not a one-shot read) so @AppStorage keeps it reactive: toggling either setting
/// updates every mounted tab in place. Mirrors the Android `LiquidScreenSky(fillHeight:)` +
/// `fullBleedBackground` pairing.
struct LiquidScaffoldSky: View {
    var height: CGFloat = 240
    @AppStorage(SceneBackgroundPrefs.enabledKey) private var showDayCycleBackground = SceneBackgroundPrefs.defaultEnabled
    @AppStorage(SkyBehindCardsPrefs.enabledKey) private var skyBehindCards = true
    // The custom-background store (#custom-background). A custom image OVERRIDES the sky and always fills
    // the viewport, so every scaffold that passes `liquidScaffoldSky()` reads the SAME cached image and
    // draws it identically — seamless across tabs including More.
    @ObservedObject private var backgroundStore = BackgroundImageStore.shared

    var body: some View {
        if backgroundStore.isActive {
            BackgroundImageBackdrop()
        } else if showDayCycleBackground {
            LiquidSkyStatic(hour: nil, settleStrength: skyBehindCards ? 0.78 : 1)
                .frame(maxWidth: .infinity, maxHeight: skyBehindCards ? .infinity : nil)
                .frame(height: skyBehindCards ? nil : height, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

func liquidScaffoldSky(height: CGFloat = 240) -> AnyView {
    AnyView(LiquidScaffoldSky(height: height))
}

/// A STATIC time-of-day sky, rendered ONCE (no TimelineView → CoreAnimation caches it as a stable layer,
/// zero per-frame cost) for the scaffold backgrounds on the chart-heavy tabs. An always-animating Canvas
/// behind the charts stole frame headroom and caused stutter (2026-07-02); this is the same look
/// minus the twinkle/breath, matching the classic app's static scene image for scroll perf.
struct LiquidSkyStatic: View {
    var hour: Double?
    /// See `LiquidSky.settleStrength` — 1 = default seamless fade; <1 holds the atmosphere for the
    /// full-height "sky behind cards" backdrop.
    var settleStrength: Double = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let h = hour ?? LiquidSkyPaint.liveHour()
        let dark = scheme == .dark
        let settle = LiquidSkyPaint.settleColor(dark: dark)
        Canvas { ctx, size in
            let S = liquidSkyAt(h, light: !dark)
            LiquidSkyPaint.base(ctx, size, top: S.top, mid: S.mid, hor: S.hor)
            if S.stars > 0.01 { LiquidSkyPaint.stars(ctx, size, amount: S.stars, now: nil) }
            LiquidSkyPaint.settle(ctx, size, color: settle, strength: settleStrength)
        }
    }
}
