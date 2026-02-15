import XCTest
@testable import QRFlow

final class ScanabilityTests: XCTestCase {

    func testBlackOnWhiteContrastIs21() {
        XCTAssertEqual(Scanability.contrastRatio(fg: "#000000", bg: "#FFFFFF"), 21.0, accuracy: 0.1)
    }

    func testIdenticalColorsHaveUnitContrast() {
        XCTAssertEqual(Scanability.contrastRatio(fg: "#112233", bg: "#112233"), 1.0, accuracy: 0.001)
    }

    func testDefaultDesignScoresExcellent() {
        let report = Scanability.score(payload: "https://github.com", design: DesignOptions())
        XCTAssertGreaterThanOrEqual(report.score, 90)
        XCTAssertEqual(report.grade, "Excellent")
        XCTAssertTrue(report.checks.allSatisfy { $0.status != .fail })
    }

    func testLowContrastIsPenalized() {
        var d = DesignOptions()
        d.fgHex = "#CCCCCC"
        let report = Scanability.score(payload: "https://github.com", design: d)
        XCTAssertEqual(report.checks.first { $0.id == "contrast" }?.status, .fail)
    }

    func testQuietZoneBelowISOIsFlagged() {
        var d = DesignOptions()
        d.quietModules = 1
        let report = Scanability.score(payload: "https://github.com", design: d)
        XCTAssertEqual(report.checks.first { $0.id == "quiet" }?.status, .fail)
    }

    func testOversizedLogoRequiresHigherErrorCorrection() {
        var d = DesignOptions()
        d.logoPNG = Data([0x89, 0x50]) // presence is what matters
        d.logoScale = 0.5 // (1.28×0.5)² = 41% real occlusion incl. clear-zone
        d.errorLevel = .l // 7 % recovery
        let report = Scanability.score(payload: "https://github.com", design: d)
        XCTAssertEqual(report.checks.first { $0.id == "logo" }?.status, .fail)

        // RoundTripTests measured: 0.5 scale does NOT decode even at EC-H —
        // the score must keep failing. Shrinking to 0.35 (20% occlusion,
        // empirically decodable) is the fix the app should recommend.
        d.errorLevel = .h // 30 % recovery
        let stillBad = Scanability.score(payload: "https://github.com", design: d)
        XCTAssertEqual(stillBad.checks.first { $0.id == "logo" }?.status, .fail)

        d.logoScale = 0.35
        let fixed = Scanability.score(payload: "https://github.com", design: d)
        XCTAssertEqual(fixed.checks.first { $0.id == "logo" }?.status, .pass)
    }

    func testLinearCodesUseGS1QuietZoneRules() {
        // The ISO 4-module QR rule is dangerously wrong for retail barcodes:
        // GS1 requires 11 modules left of an EAN-13.
        var d = DesignOptions()
        d.symbology = .ean13
        d.quietModules = 4 // passes for QR, must fail here
        let ean = Scanability.score(payload: "4006381333931", design: d)
        XCTAssertEqual(ean.checks.first { $0.id == "quiet" }?.status, .fail)

        d.quietModules = 11
        let ok = Scanability.score(payload: "4006381333931", design: d)
        XCTAssertEqual(ok.checks.first { $0.id == "quiet" }?.status, .pass)

        d.symbology = .code128
        d.quietModules = 6
        let c128 = Scanability.score(payload: "ABC-123", design: d)
        XCTAssertEqual(c128.checks.first { $0.id == "quiet" }?.status, .warn)
    }

    func testDensePayloadWarns() {
        // 400 bytes at EC Q lands at version 20 — the top of the "warn" band.
        let dense = String(repeating: "x", count: 400)
        let report = Scanability.score(payload: dense, design: DesignOptions())
        XCTAssertEqual(report.checks.first { $0.id == "density" }?.status, .warn)
    }

    func testVeryDensePayloadFailsDensityCheck() {
        // 900 bytes at EC Q needs ~version 32 — past the warn band, must fail.
        let dense = String(repeating: "x", count: 900)
        let report = Scanability.score(payload: dense, design: DesignOptions())
        XCTAssertEqual(report.checks.first { $0.id == "density" }?.status, .fail)
    }
}
