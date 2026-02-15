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
            // Record the actual decode boundary in the test log — the
            // occlusion thresholds in Scanability should be set from THIS.
            print("ROUNDTRIP logoScale=\(String(format: "%.2f", scale)) decodes=\(decode(img) == payload)")
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
