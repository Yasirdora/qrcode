import XCTest
@testable import QRFlow

/// Pins the styled-QR pipeline: matrix extraction, finder detection, every
/// module shape rendering, and the scanability rules that price the style.
final class StyledQRTests: XCTestCase {

    private let payload = "https://github.com"

    // MARK: - Matrix extraction

    func testMatrixHasSquareGridMatchingExtent() {
        guard let (grid, n) = StyledQRRenderer.matrix(payload: payload, ec: .q) else {
            return XCTFail("matrix extraction failed")
        }
        XCTAssertGreaterThanOrEqual(n, 21) // version 1 is 21×21
        XCTAssertEqual(grid.count, n * n)
    }

    func testFinderBlocksDetectedAtThreeCorners() {
        guard let (grid, n) = StyledQRRenderer.matrix(payload: payload, ec: .q) else {
            return XCTFail("matrix extraction failed")
        }
        let blocks = StyledQRRenderer.finderBlocks(grid: grid, n: n)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertTrue(blocks.contains { $0.row == 0 && $0.col == 0 })
        XCTAssertTrue(blocks.contains { $0.row == 0 && $0.col == n - 7 })
        XCTAssertTrue(blocks.contains { $0.row == n - 7 && $0.col == 0 })
    }

    // MARK: - Rendering

    func testEveryDotStyleRenders() {
        for dot in DotType.allCases {
            var d = DesignOptions()
            d.dotType = dot
            XCTAssertNotNil(QRRenderer.image(payload: payload, design: d), "dotType \(dot.rawValue) failed to render")
        }
    }

    func testCircularEyesRender() {
        var d = DesignOptions()
        d.cornerSquareType = .dot
        d.cornerDotType = .dot
        XCTAssertNotNil(QRRenderer.image(payload: payload, design: d))
    }

    func testGradientRenders() {
        var d = DesignOptions()
        d.gradientEnabled = true
        XCTAssertNotNil(QRRenderer.image(payload: payload, design: d))
    }

    func testTransparentBackgroundRenders() {
        var d = DesignOptions()
        d.transparentBg = true
        XCTAssertNotNil(QRRenderer.image(payload: payload, design: d))
    }

    func testPlainStyleKeepsClassicPath() {
        // Default design must NOT route to the styled renderer.
        XCTAssertTrue(DesignOptions().isPlainStyle)
        var d = DesignOptions()
        d.dotType = .rounded
        XCTAssertFalse(d.isPlainStyle)
    }

    // MARK: - Scanability rules

    func testDotModulesWarn() {
        var d = DesignOptions()
        d.dotType = .dots
        let report = Scanability.score(payload: payload, design: d)
        XCTAssertEqual(report.checks.first { $0.id == "style" }?.status, .warn)
    }

    func testTransparentBackgroundWarns() {
        var d = DesignOptions()
        d.transparentBg = true
        let report = Scanability.score(payload: payload, design: d)
        XCTAssertEqual(report.checks.first { $0.id == "style" }?.status, .warn)
    }

    func testRoundedModulesPass() {
        var d = DesignOptions()
        d.dotType = .rounded
        let report = Scanability.score(payload: payload, design: d)
        XCTAssertEqual(report.checks.first { $0.id == "style" }?.status, .pass)
    }

    func testLegacyDotStylesMigrateToRounded() throws {
        // Designs saved before the vocabulary trim used retired styles;
        // decoding must not fail — they map to the closest surviving shape.
        for legacy in ["classy", "classyRounded", "extraRounded"] {
            let data = Data("\"\(legacy)\"".utf8)
            let decoded = try JSONDecoder().decode(DotType.self, from: data)
            XCTAssertEqual(decoded, .rounded, "\(legacy) should migrate to rounded")
        }
        // And the surviving vocabulary round-trips unchanged.
        for type in DotType.allCases {
            let data = try JSONEncoder().encode(type)
            XCTAssertEqual(try JSONDecoder().decode(DotType.self, from: data), type)
        }
    }

    func testGradientUsesWeakestEndForContrast() {
        // Black modules alone give 21:1 — but a light gradient end is what
        // the scanner actually faces at that corner of the symbol.
        var d = DesignOptions()
        d.gradientEnabled = true
        d.gradientColor2Hex = "#CCCCCC"
        let report = Scanability.score(payload: payload, design: d)
        XCTAssertEqual(report.checks.first { $0.id == "contrast" }?.status, .fail)
    }

    func testStyleCheckDoesNotPunishDefaultDesign() {
        let report = Scanability.score(payload: payload, design: DesignOptions())
        XCTAssertEqual(report.checks.first { $0.id == "style" }?.status, .pass)
        XCTAssertGreaterThanOrEqual(report.score, 90)
    }

    func testEveryPresetKeepsScannerSafeContrast() {
        // Presets are one-tap themes a user may apply blindly — none of them
        // may ship a foreground/background pairing a scanner can't read.
        for preset in DesignPreset.allCases {
            var d = DesignOptions()
            preset.apply(to: &d)
            let report = Scanability.score(payload: payload, design: d)
            XCTAssertNotEqual(report.checks.first { $0.id == "contrast" }?.status, .fail,
                              "\(preset) preset must not fail contrast")
        }
    }

    // MARK: - Fluid (neighbor-aware) modules

    func testFluidStyleRenders() {
        var d = DesignOptions()
        d.dotType = .fluid
        XCTAssertNotNil(QRRenderer.image(payload: payload, design: d))
    }

    func testFluidStyleKeepsFullInkCoverage() {
        // Fluid corners only round where they face empty space; merged runs
        // keep full coverage, so the style check must pass like rounded.
        var d = DesignOptions()
        d.dotType = .fluid
        let report = Scanability.score(payload: payload, design: d)
        XCTAssertEqual(report.checks.first { $0.id == "style" }?.status, .pass)
    }

    func testFluidGradientComboRenders() {
        // Fluid modules feed the same even-odd clip path as every other
        // style — gradient fill must work identically.
        var d = DesignOptions()
        d.dotType = .fluid
        d.gradientEnabled = true
        d.gradientColor2Hex = "#0369A1"
        XCTAssertNotNil(QRRenderer.image(payload: payload, design: d))
    }

    func testFluidIsVisibleWithoutScrollingInGalleryOrder() {
        // The Dot shape gallery truncates after ~5 swatches on screen. Fluid
        // buried at the end made it undiscoverable — users could only get the
        // look via the Flow theme. It must stay in the first screenful.
        XCTAssertLessThanOrEqual(DotType.allCases.firstIndex(of: .fluid)!, 3)
    }

    func testWideGamutColorHexRoundTripsSafely() {
        // A Display P3 color has components > 1.0 in extended sRGB; the old
        // hexString turned bright red into "#1160000" → parsed as near-black.
        let p3Red = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1).hexString
        XCTAssertEqual(p3Red.count, 7)
        XCTAssertEqual(p3Red, "#FF0000")
        // In-gamut colors must not drift (rounding, not truncation).
        let mid = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1).hexString
        XCTAssertEqual(mid, "#808080")
    }
}
