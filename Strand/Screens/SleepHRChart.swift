import SwiftUI
import StrandDesign
import WhoopStore

/// WHOOP's sleeping heart-rate chart: a thin HR trace across the night with dashed onset/wake rules and
/// quiet bpm gridlines. With a stage selected, the trace re-colours inside that stage's intervals and those
/// time columns get a faint stage-tinted wash — WHOOP's "what did my heart do during REM" read.
/// Canvas-drawn (~550 one-minute buckets); gaps in the data break the line honestly rather than
/// interpolating across them.
///
/// Fork: hold and drag reads the night out minute by minute — a crosshair, the sampled point and a tooltip
/// with the clock time, the bpm and the stage at that moment. Lifted out of `SleepView` (3 000 lines) when
/// the scrub went in, so the Canvas and the overlay can share ONE x-mapping (`x(rel:in:)`): the two
/// existing scrubs in this app both warn that a second copy of the mapping is where a crosshair starts
/// lying about which sample it is on.
struct SleepHRChart: View {
    /// One-minute HR buckets covering the night, oldest first (`Repository.hrBuckets`).
    let buckets: [HRBucket]
    /// The night's display-smoothed stage intervals, in seconds from `nightStartTs`.
    let intervals: [SleepInterval]
    /// The chart's x-window, in seconds from `nightStartTs`.
    let origin: TimeInterval
    let span: TimeInterval
    /// Unix time of the night's onset — the zero of `origin` / `span` and of `intervals`.
    let nightStartTs: TimeInterval
    /// The stage the user selected under the chart, if any: it tints the trace and washes its columns.
    let selectedStage: SleepStage?

    /// The scrub's x in the chart's own space. nil when the finger is off the chart.
    @State private var scrubX: CGFloat?
    /// True from the moment a hold is recognised, so the engage haptic fires once per scrub.
    @State private var scrubEngaged = false

    private static let clock: DateFormatter = AppClock.hourMinuteFormatter()

    var body: some View {
        if buckets.count >= 2 {
            GeometryReader { geo in
                ZStack {
                    canvas
                    scrubOverlay(in: geo.size)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            #if os(iOS)
            .gesture(touchScrubGesture)
            #endif
            .accessibilityLabel(Text("Sleeping heart rate through the night"))
        } else {
            Text("No heart-rate detail for this night")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: Geometry (one mapping, shared by the Canvas and the scrub overlay)

    private var bpmRange: (lo: Double, hi: Double) {
        let bpms = buckets.map(\.bpm)
        return ((bpms.min() ?? 40) - 5, (bpms.max() ?? 90) + 5)
    }

    private func x(rel: TimeInterval, in size: CGSize) -> CGFloat {
        CGFloat((rel - origin) / span) * size.width
    }

    private func point(_ b: HRBucket, in size: CGSize) -> CGPoint {
        let r = bpmRange
        return CGPoint(x: x(rel: TimeInterval(b.ts) - nightStartTs, in: size),
                       y: size.height * (1 - CGFloat((b.bpm - r.lo) / max(1, r.hi - r.lo))))
    }

    /// The stage covering a moment, for the tooltip's second line.
    private func stage(atRel rel: TimeInterval) -> SleepStage? {
        intervals.first { rel >= $0.start && rel <= $0.end }?.stage
    }

    // MARK: Trace

    private var canvas: some View {
        Canvas { ctx, size in
            let r = bpmRange
            let (lo, hi) = (r.lo, r.hi)
            // Selected-stage column washes UNDER everything else.
            if let sel = selectedStage {
                let wash = StrandPalette.sleepStageColor(sel).opacity(0.13)
                for iv in intervals where iv.stage == sel {
                    let x0 = x(rel: iv.start, in: size)
                    let w = max(1, CGFloat((iv.end - iv.start) / span) * size.width)
                    ctx.fill(Path(CGRect(x: x0, y: 0, width: w, height: size.height)), with: .color(wash))
                }
            }
            // Quiet bpm gridlines + labels at ~3 nice values.
            let step = max(10.0, (((hi - lo) / 3) / 10).rounded() * 10)
            var grid = (lo / step).rounded(.up) * step
            while grid < hi {
                let y = size.height * (1 - CGFloat((grid - lo) / max(1, hi - lo)))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(StrandPalette.hairline.opacity(0.5)), lineWidth: 1)
                ctx.draw(Text(verbatim: "\(Int(grid))").font(.system(size: 9)).foregroundColor(StrandPalette.textTertiary),
                         at: CGPoint(x: 10, y: y - 7))
                grid += step
            }
            // Base trace across the whole night; the line BREAKS across >5-min data gaps.
            // Split by signal confidence: clean/measured HR draws solid, weak-optical stretches
            // (PPG conf < 0.3) draw lighter + dashed, so a weak estimate is never presented as a
            // clean measured beat. NOTE: with the default acceptance floor (0.3) no stored PPG
            // sample carries conf < 0.3, so this weak branch is inert unless a future opt-in
            // weak-signal mode (which needs a faithfulness eval first) lowers the floor.
            let baseColor = selectedStage == nil
                ? StrandPalette.restColor.opacity(0.9)
                : StrandPalette.textTertiary.opacity(0.45)
            var strong = Path()
            var weakPath = Path()
            var prev: (ts: Int, pt: CGPoint, strong: Bool)? = nil
            for b in buckets {
                let p = point(b, in: size)
                let isStrong = b.conf >= 0.3
                if let pr = prev, b.ts - pr.ts <= 300 {
                    // Bridge class transitions from the previous point so the trace stays
                    // continuous — the weak segment owns the bridging stroke.
                    if isStrong {
                        if pr.strong { strong.addLine(to: p) }
                        else { strong.move(to: pr.pt); strong.addLine(to: p) }
                    } else {
                        if !pr.strong { weakPath.addLine(to: p) }
                        else { weakPath.move(to: pr.pt); weakPath.addLine(to: p) }
                    }
                } else {
                    if isStrong { strong.move(to: p) } else { weakPath.move(to: p) }
                }
                prev = (b.ts, p, isStrong)
            }
            ctx.stroke(strong, with: .color(baseColor), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            ctx.stroke(weakPath, with: .color(baseColor.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, lineJoin: .round, dash: [2, 3]))
            // Selected-stage trace overlay: the HR line re-drawn in the stage colour, only
            // inside that stage's intervals.
            if let sel = selectedStage {
                let ranges = intervals.filter { $0.stage == sel }.map { ($0.start, $0.end) }
                var overlay = Path()
                var lastIn: Int? = nil
                for b in buckets {
                    let rel = TimeInterval(b.ts) - nightStartTs
                    let inside = ranges.contains { rel >= $0.0 && rel <= $0.1 }
                    if inside {
                        let p = point(b, in: size)
                        if let last = lastIn, b.ts - last <= 300 { overlay.addLine(to: p) } else { overlay.move(to: p) }
                        lastIn = b.ts
                    } else {
                        lastIn = nil
                    }
                }
                ctx.stroke(overlay, with: .color(StrandPalette.sleepStageColor(sel)),
                           style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            // Dashed onset/wake rules (WHOOP's sleep-window markers).
            for x in [CGFloat(0.75), size.width - 0.75] {
                var rule = Path()
                rule.move(to: CGPoint(x: x, y: 0)); rule.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(rule, with: .color(StrandPalette.textTertiary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    // MARK: Scrub

    /// The crosshair, the sampled point and the read-out, drawn over the trace while a finger is down.
    @ViewBuilder
    private func scrubOverlay(in size: CGSize) -> some View {
        if let scrubX, size.width > 0,
           let i = ChartHoverMath.nearestIndex(toX: scrubX,
                                               xs: buckets.map { x(rel: TimeInterval($0.ts) - nightStartTs, in: size) }) {
            let bucket = buckets[i]
            let anchor = point(bucket, in: size)
            let rel = TimeInterval(bucket.ts) - nightStartTs
            let stageHere = stage(atRel: rel)
            let tint = stageHere.map { StrandPalette.sleepStageColor($0) } ?? StrandPalette.restColor
            CrosshairRule(x: anchor.x, height: size.height)
            HighlightDot(color: tint).position(anchor)
            PositionedTooltip(
                anchor: anchor,
                container: size,
                tooltip: ChartTooltip(
                    value: "\(Int(bucket.bpm.rounded())) bpm",
                    // The clock time the sample was taken, then the stage it fell in. A bucket is a
                    // one-minute MEAN, so the range is named when the minute actually moved.
                    label: [Self.clock.string(from: Date(timeIntervalSince1970: TimeInterval(bucket.ts))),
                            stageHere.map(Self.stageName),
                            Int(bucket.maxBpm.rounded()) - Int(bucket.minBpm.rounded()) >= 3
                                ? "\(Int(bucket.minBpm.rounded()))–\(Int(bucket.maxBpm.rounded()))" : nil]
                        .compactMap { $0 }.joined(separator: " · "),
                    accent: tint))
        }
    }

    private static func stageName(_ stage: SleepStage) -> String {
        switch stage {
        case .awake: return String(localized: "Awake")
        case .light: return String(localized: "Light")
        case .deep:  return String(localized: "Deep")
        case .rem:   return String(localized: "REM")
        }
    }

    #if os(iOS)
    /// Hold, then drag. The sleep screen scrolls vertically, so a bare `DragGesture` would fight the
    /// ScrollView; the 0.25 s / 8 pt hold is the same gate `OverviewHRChart` and Liquid Today use, and the
    /// transaction keeps the crosshair from animating after the finger (TrendChart #104).
    private var touchScrubGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !scrubEngaged {
                    scrubEngaged = true
                    StrandHaptic.selection.play()
                }
                if let drag {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { scrubX = drag.location.x }
                }
            }
            .onEnded { _ in
                scrubEngaged = false
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { scrubX = nil }
            }
    }
    #endif
}
