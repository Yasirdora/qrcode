import XCTest
import Vision
@testable import QRFlow

/// The test a QR generator most needs: render a code, then decode it back
/// with the same Vision framework real scanners use. This is what turns the
/// scanability score from a heuristic into a measured claim.
final class RoundTripTests: XCTestCase {

    private let payload = "https://example.com/some/realistic/path?utm=qr"

    /// Decode the first QR payload from a rendered image, or nil.
    private func decode(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard let cg = image.cgImage else {
            XCTFail("rendered image has no CGImage backing", file: file, line: line)
            return nil
        }
        var result: String?
        // Revision 1 is the classical detector — revisions 2+ require a
        // neural inference context that headless simulators can't create
        // ("Could not create inference context", Vision error 9).
        let request = VNDetectBarcodesRequest { req, _ in
            let obs = (req.results as? [VNBarcodeObservation])?.first
            result = obs?.payloadStringValue
            if obs == nil { print("ROUNDTRIP-DEBUG vision ran, zero observations") }
        }
        request.revision = VNDetectBarcodesRequestRevision1
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        } catch {
            print("ROUNDTRIP-DEBUG vision perform threw: \(error)")
        }
        return result
    }

    /// Every module style, at every error-correction level, must scan.
    func testEveryStyleAndErrorLevelDecodesBack() {
        for style in DotType.allCases {
            for ec in ErrorLevel.allCases {
                var d = DesignOptions()
                d.dotType = style
                d.errorLevel = ec
                guard let img = QRRenderer.image(payload: payload, design: d) else {
                    XCTFail("\(style)/\(ec) did not render")
                    continue
                }
                XCTAssertEqual(decode(img), payload, "\(style)/\(ec) failed to decode")
            }
        }
    }

    /// The logo slider's usable range must be backed by decodability at the
    /// strongest error correction — this test defines where the safe ceiling
    /// actually is, empirically, instead of by rule of thumb.
    func testLogoOcclusionDecodabilityCurve() {
        for scale in stride(from: 0.10, through: 0.50, by: 0.05) {
            var d = DesignOptions()
            d.errorLevel = .h
            d.logoScale = scale
            d.logoPNG = Self.solidLogo
            guard let img = QRRenderer.image(payload: payload, design: d) else {
                XCTFail("logo \(scale) did not render")
                continue
            }
            let decodes = decode(img) == payload
            // Printed so the boundary stays visible in the test log …
            print("ROUNDTRIP logoScale=\(String(format: "%.2f", scale)) decodes=\(decodes)")
            // … and asserted where the shipping UI must hold. The design sheet
            // caps the slider at 0.35, so everything at or below that has to
            // scan at EC-H. That assertion is what turns the cap from a rule of
            // thumb into a measured claim. Above the cap the curve is recorded
            // but not required.
            if scale <= 0.35 {
                XCTAssertTrue(decodes, "logo at \(scale) must still decode — the slider allows it")
            }
        }
    }

    /// Gradient styles use the weakest end for contrast — verify the extreme
    /// still scans when both ends are dark.
    func testGradientDecodesBack() {
        var d = DesignOptions()
        d.gradientEnabled = true
        d.gradientColor2Hex = "#0369A1"
        guard let img = QRRenderer.image(payload: payload, design: d) else {
            XCTFail("gradient did not render")
            return
        }
        XCTAssertEqual(decode(img), payload)
    }

    /// A long payload pushes module density to the edge of legibility.
    func testDensePayloadDecodesBack() {
        let dense = String(repeating: "https://example.com/catalog/item/", count: 20)
        let img = QRRenderer.image(payload: dense, design: DesignOptions())
        XCTAssertNotNil(img)
        if let img { XCTAssertEqual(decode(img), dense) }
    }

    /// Nothing else decodes a linear symbol, so until this existed no test
    /// proved an EAN or Code 128 code actually scans — the render tests only
    /// proved they produced an image. Bars that land on fractional pixels, or
    /// a check digit the encoder gets wrong, fail here.
    func testLinearSymbologiesDecodeBack() {
        let cases: [(Symbology, String)] = [
            (.ean13, "4006381333931"),
            (.ean8, "96385074"),
            (.code128, "QRCODE-2026"),
        ]
        for (symbology, value) in cases {
            var d = DesignOptions()
            d.symbology = symbology
            d.exportSize = 1024
            guard let img = QRRenderer.image(payload: value, design: d) else {
                XCTFail("\(symbology.rawValue) did not render")
                continue
            }
            XCTAssertEqual(decode(img), value, "\(symbology.rawValue) failed to decode")
        }
    }

    // MARK: - SVG export

    /// The vector export has to describe the same symbol as the raster one:
    /// every dark module outside the finder patterns becomes one subpath, and
    /// each eye adds its ring and its centre dot.
    func testSVGSubpathCountMatchesTheMatrix() {
        var design = DesignOptions()
        design.dotType = .square
        guard let svg = QRRenderer.svg(payload: payload, design: design),
              let (grid, n) = StyledQRRenderer.matrix(payload: payload, ec: design.errorLevel),
              let dStart = svg.range(of: "<path d=\""),
              let dEnd = svg.range(of: "\" fill=", range: dStart.upperBound..<svg.endIndex) else {
            return XCTFail("no SVG path produced")
        }
        // Well-formed XML, not merely a string that starts with <svg.
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse(), "the SVG is not well-formed")

        let finders = StyledQRRenderer.finderBlocks(grid: grid, n: n)
        func insideFinder(_ r: Int, _ c: Int) -> Bool {
            finders.contains { r >= $0.row && r < $0.row + 7 && c >= $0.col && c < $0.col + 7 }
        }
        var expected = 0
        for r in 0..<n {
            for c in 0..<n where grid[r * n + c] && !insideFinder(r, c) { expected += 1 }
        }
        expected += finders.count * 3 // ring outer, ring inner, centre dot

        let subpaths = svg[dStart.upperBound..<dEnd.lowerBound].filter { $0 == "M" }.count
        XCTAssertEqual(subpaths, expected, "one subpath per module and per eye shape")
    }

    /// Gradient, Context Band and text escaping all have to survive the trip
    /// into vector output.
    func testSVGCarriesTheGradientAndTheContextBand() {
        var design = DesignOptions()
        design.exportSize = 512
        design.gradientEnabled = true
        design.gradientColor2Hex = "#0369A1"
        design.ctaEnabled = true
        design.ctaText = "Scan <me> & enjoy"
        guard let svg = QRRenderer.svg(payload: payload, design: design) else {
            return XCTFail("no SVG produced")
        }
        XCTAssertTrue(svg.contains("<linearGradient"), "a gradient design must define one")
        XCTAssertTrue(svg.contains("fill=\"url(#modules)\""), "the modules must reference it")
        XCTAssertTrue(svg.contains("stop-color=\"#0369A1\""), "the gradient end colour must appear")
        // 512 × 0.24 rounded = 123pt of band, so the canvas grows to 635.
        XCTAssertTrue(svg.contains("height=\"635\""), "the band adds height to the canvas")
        XCTAssertTrue(svg.contains("Scan &lt;me&gt; &amp; enjoy"), "band text must be XML-escaped")
    }

    func testSVGOmitsTheBackgroundWhenTransparentAndRefusesLinearCodes() {
        var transparent = DesignOptions()
        transparent.transparentBg = true
        guard let svg = QRRenderer.svg(payload: payload, design: transparent) else {
            return XCTFail("no SVG produced")
        }
        XCTAssertFalse(svg.contains("<rect width="), "a transparent design ships no background")

        var ean = DesignOptions()
        ean.symbology = .ean13
        XCTAssertNil(QRRenderer.svg(payload: "4006381333931", design: ean),
                     "a linear code has no module geometry to serialise")
    }

    /// 64×64 mid-gray square — stands in for any user logo.
    private static let solidLogo: Data = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let img = r.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        return img.pngData()!
    }()
}
