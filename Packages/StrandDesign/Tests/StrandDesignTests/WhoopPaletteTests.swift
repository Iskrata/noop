import XCTest
import SwiftUI
@testable import StrandDesign

/// Pins the WHOOP chart-style contract (#whoop-palette): the recovery bands land exactly on WHOOP's own
/// published thresholds (High ≥67, Medium 34-66, Low ≤33 — see the sourced comment above
/// `StrandPalette.whoopRecoveryGreen`), and `.whoop` is the fork's default everywhere `ChartStyle`
/// resolves a raw value or falls back.
final class WhoopPaletteTests: XCTestCase {
    private var savedChartStyle: ChartStyle!

    override func setUp() {
        super.setUp()
        savedChartStyle = StrandPalette.chartStyle
    }

    override func tearDown() {
        StrandPalette.chartStyle = savedChartStyle
        super.tearDown()
    }

    func testWhoopIsTheDefaultChartStyle() {
        XCTAssertEqual(ChartStyle.resolve("nonsense"), .whoop)
        XCTAssertEqual(ChartStyle.resolve(""), .whoop)
    }

    func testWhoopIsTheDefaultThemePreset() {
        XCTAssertEqual(ThemePreset.resolve("nonsense"), .whoop)
    }

    func testWhoopIsTheDefaultAccentColor() {
        XCTAssertEqual(AccentColor.resolve("nonsense"), .whoopBlue)
    }

    func testWhoopThemePresetRecipe() {
        let recipe = ThemePreset.whoop.recipe
        XCTAssertEqual(recipe?.accent, .whoopBlue)
        XCTAssertEqual(recipe?.chart, .whoop)
    }

    /// WHOOP's own recovery-band thresholds: High 100-67%, Medium 66-34%, Low 33-0%. Sampling the
    /// gradient at a fraction just inside / outside each edge must land on the correct flat colour — the
    /// WHOOP ring renders a solid arc per band, not a blend between them.
    /// `Color` equality is NOT reliable across two different construction paths for the same visual
    /// colour (a literal `Color(hex:)` vs. one rebuilt by `sample(stops:at:)`'s sRGB interpolation), so —
    /// like every other colour assertion in this package (see `PlaceholderTests`) — this compares
    /// resolved RGBA components with a tolerance instead of `Color` values directly.
    private func assertSameColor(_ a: Color, _ b: Color, accuracy: Double = 0.02,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let ca = a.rgbaComponents, cb = b.rgbaComponents
        XCTAssertEqual(ca.r, cb.r, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(ca.g, cb.g, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(ca.b, cb.b, accuracy: accuracy, file: file, line: line)
    }

    func testRecoveryBandsMatchWhoopThresholds() {
        StrandPalette.chartStyle = .whoop
        assertSameColor(StrandPalette.recoveryColor(0), StrandPalette.whoopRecoveryRed)
        assertSameColor(StrandPalette.recoveryColor(33), StrandPalette.whoopRecoveryRed)
        assertSameColor(StrandPalette.recoveryColor(34), StrandPalette.whoopRecoveryYellow)
        assertSameColor(StrandPalette.recoveryColor(66), StrandPalette.whoopRecoveryYellow)
        assertSameColor(StrandPalette.recoveryColor(67), StrandPalette.whoopRecoveryGreen)
        assertSameColor(StrandPalette.recoveryColor(100), StrandPalette.whoopRecoveryGreen)
    }

    func testDomainColoursUseWhoopBrandHexesWhenWhoopIsActive() {
        StrandPalette.chartStyle = .whoop
        // Fork palette: Recovery green and Sleep violet; Effort keeps WHOOP's Strain blue.
        assertSameColor(StrandPalette.chargeColor, StrandPalette.forkRecovery)
        assertSameColor(StrandPalette.effortColor, StrandPalette.whoopStrain)
        assertSameColor(StrandPalette.restColor, StrandPalette.forkSleep)
        assertSameColor(StrandPalette.statusPositive, StrandPalette.whoopRecoveryGreen)
        assertSameColor(StrandPalette.statusWarning, StrandPalette.whoopRecoveryYellow)
        assertSameColor(StrandPalette.statusCritical, StrandPalette.whoopRecoveryRed)
    }

    /// Sourced verbatim from WHOOP's official Brand & Design Guidelines PDF, "WHOOP – Color Palette"
    /// page (fetched 2026-09-17) — see the citation above `StrandPalette.whoopStrain`. Pinning the raw
    /// hexes here (rather than only the derived Color values above) documents exactly what was sourced
    /// vs. derived, and catches an accidental edit to the wrong literal.
    func testSourcedHexesMatchTheWhoopBrandGuidelines() {
        // Dark-mode values ARE the verbatim brand hexes (WHOOP ships dark-only). Compare against a
        // `Color` built directly from each brand-guideline hex, rather than restating the literal as an
        // equality check, so an accidental edit to the wrong hex still fails this test.
        func rgba(_ c: Color) -> (r: Double, g: Double, b: Double, a: Double) { c.rgbaComponents }
        // Fork: the band colours are softened a step from the brand's #16EC06 / #FFDE00 / #FF0026.
        XCTAssertEqual(rgba(StrandPalette.whoopRecoveryGreen).r, rgba(Color(hex: "#3CD65A")).r, accuracy: 0.001)
        XCTAssertEqual(rgba(StrandPalette.whoopRecoveryYellow).g, rgba(Color(hex: "#F5C518")).g, accuracy: 0.001)
        XCTAssertEqual(rgba(StrandPalette.whoopRecoveryRed).r, rgba(Color(hex: "#F2465A")).r, accuracy: 0.001)
    }
}
