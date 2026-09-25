import Foundation
import WhoopProtocol

/// Fork: which wall-clock minutes the wearer was still, from the strap's own motion magnitude
/// (`GravitySample.dynAccel`, gravity-removed, in g). The irregular-rhythm and breathing-disturbance
/// screens only read minutes where the wrist was still: the optical beat train is dominated by motion
/// artifact otherwise.
///
/// A minute is still when it holds at least one `dynAccel` reading and every reading in it is below
/// `maxDynAccelG`. A minute with no reading is NOT still — unknown motion is treated as motion.
///
/// Threshold 0.1 g, chosen on the owner's 45-day history (2026-09-25): it keeps 63% of beat-covered
/// minutes and cuts minutes the rhythm detector flags from 3.3% to 0.87%.
public enum MotionStillness {
    public static let maxDynAccelG = 0.1

    /// Minute indices (`ts / 60`) in which the wrist was still.
    public static func stillMinutes(_ gravity: [GravitySample], maxDynAccelG: Double = maxDynAccelG) -> Set<Int> {
        var maxByMinute: [Int: Double] = [:]
        for g in gravity {
            guard let d = g.dynAccel else { continue }
            let m = Int((Double(g.ts) / 60).rounded(.down))
            maxByMinute[m] = max(maxByMinute[m] ?? 0, d)
        }
        return Set(maxByMinute.compactMap { $0.value < maxDynAccelG ? $0.key : nil })
    }
}
