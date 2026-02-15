import XCTest
@testable import QRFlow

/// Pins the hand-rolled GS1 encoder against known-good retail barcodes.
final class EANEncoderTests: XCTestCase {

    func testKnownCheckDigits() {
        // 4006381333931 — a real EAN-13 (Stabilo highlighter).
        XCTAssertEqual(EANEncoder.checkDigit(body: [4, 0, 0, 6, 3, 8, 1, 3, 3, 3, 9, 3], kind: .ean13), 1)
        // 96385074 — a valid EAN-8.
        XCTAssertEqual(EANEncoder.checkDigit(body: [9, 6, 3, 8, 5, 0, 7], kind: .ean8), 4)
    }

    func testNormalizeAppendsAndValidatesCheckDigit() {
        XCTAssertEqual(EANEncoder.normalized("400638133393", kind: .ean13), "4006381333931")
        XCTAssertEqual(EANEncoder.normalized("4006381333931", kind: .ean13), "4006381333931")
        XCTAssertEqual(EANEncoder.normalized("9638507", kind: .ean8), "96385074")
        XCTAssertEqual(EANEncoder.normalized("96385074", kind: .ean8), "96385074")
    }

    func testNormalizeRejectsBadInput() {
        XCTAssertNil(EANEncoder.normalized("4006381333932", kind: .ean13)) // wrong check digit
        XCTAssertNil(EANEncoder.normalized("12345", kind: .ean13))          // too short
        XCTAssertNil(EANEncoder.normalized("abcdefghijkl", kind: .ean13))   // non-digits
        XCTAssertNil(EANEncoder.normalized("", kind: .ean8))                // empty
    }

    func testModuleRowStructure() {
        let row13 = EANEncoder.modules("4006381333931", kind: .ean13)
        XCTAssertEqual(row13?.count, 95) // GS1 fixed length
        XCTAssertTrue(row13?.hasPrefix("101") == true)  // left guard
        XCTAssertTrue(row13?.hasSuffix("101") == true)  // right guard

        let row8 = EANEncoder.modules("96385074", kind: .ean8)
        XCTAssertEqual(row8?.count, 67)
        XCTAssertTrue(row8?.hasPrefix("101") == true)
        XCTAssertTrue(row8?.hasSuffix("101") == true)
    }

    func testLinearSymbologiesDoNotCarryRichPayloads() {
        XCTAssertFalse(Symbology.code128.carriesRichPayload)
        XCTAssertFalse(Symbology.ean13.carriesRichPayload)
        XCTAssertTrue(Symbology.aztec.carriesRichPayload)
        XCTAssertTrue(Symbology.pdf417.carriesRichPayload)
    }
}

/// Rendering smoke tests: every symbology produces a real image for valid
/// input, and invalid input fails loudly (nil) rather than rendering junk.
final class BarcodeRendererTests: XCTestCase {

    private func design(_ s: Symbology) -> DesignOptions {
        var d = DesignOptions()
        d.symbology = s
        return d
    }

    func testCoreImageSymbologiesRender() {
        for s in [Symbology.aztec, .pdf417, .code128] {
            XCTAssertNotNil(QRRenderer.image(payload: "HELLO 123", design: design(s)), "\(s.title) should render")
        }
    }

    func testEANRendersValidRejectsInvalid() {
        XCTAssertNotNil(QRRenderer.image(payload: "4006381333931", design: design(.ean13)))
        XCTAssertNotNil(QRRenderer.image(payload: "400638133393", design: design(.ean13))) // check digit appended
        XCTAssertNotNil(QRRenderer.image(payload: "96385074", design: design(.ean8)))
        XCTAssertNil(QRRenderer.image(payload: "4006381333932", design: design(.ean13)))
        XCTAssertNil(QRRenderer.image(payload: "hello", design: design(.ean8)))
    }

    func testSymbologyAwarePayloadRouting() {
        var content = ContentState()
        content.barcodeValue = "12345670"
        content.url = "https://example.com"
        XCTAssertEqual(PayloadBuilder.payload(for: content, symbology: .ean8), "12345670")
        XCTAssertEqual(PayloadBuilder.payload(for: content, symbology: .qr), "https://example.com")
    }
}

/// Per-symbology scanability: the score adapts its checks to the format.
final class SymbologyScanabilityTests: XCTestCase {

    private func design(_ s: Symbology) -> DesignOptions {
        var d = DesignOptions()
        d.symbology = s
        return d
    }

    func testValidEANPassesCheckDigitCheck() {
        let report = Scanability.score(payload: "4006381333931", design: design(.ean13))
        XCTAssertEqual(report.checks.first { $0.id == "payload" }?.status, .pass)
    }

    func testInvalidEANFailsCheckDigitCheck() {
        let report = Scanability.score(payload: "4006381333932", design: design(.ean13))
        XCTAssertEqual(report.checks.first { $0.id == "payload" }?.status, .fail)
    }

    func testCode128PayloadLimits() {
        XCTAssertEqual(Scanability.score(payload: "QRFLOW", design: design(.code128))
            .checks.first { $0.id == "payload" }?.status, .pass)
        XCTAssertEqual(Scanability.score(payload: String(repeating: "x", count: 34), design: design(.code128))
            .checks.first { $0.id == "payload" }?.status, .warn)
        XCTAssertEqual(Scanability.score(payload: "emoji 🎉", design: design(.code128))
            .checks.first { $0.id == "payload" }?.status, .fail)
    }

    func testQRReportKeepsDensityCheck() {
        let report = Scanability.score(payload: "https://github.com", design: design(.qr))
        XCTAssertNotNil(report.checks.first { $0.id == "density" })
        XCTAssertEqual(report.score, 100) // regression: default QR design still perfect
    }

    func testAztecUsesTwoDimensionalChecks() {
        let report = Scanability.score(payload: "BOARDING PASS", design: design(.aztec))
        XCTAssertNotNil(report.checks.first { $0.id == "density" })
        XCTAssertNotNil(report.checks.first { $0.id == "logo" })
    }
}
