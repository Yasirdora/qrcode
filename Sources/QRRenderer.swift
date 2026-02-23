import UIKit
import CoreImage

/// Renders QR symbols with CoreImage's native `CIQRCodeGenerator`, then
/// composites color, quiet zone, center logo and the Context Band with
/// CoreGraphics. No third-party dependency — the whole pipeline is platform.
enum QRRenderer {

    private static let ciContext = CIContext()

    // MARK: - Public API

    /// Preview/export image at the design's export size. Dispatches on the
    /// design's symbology: QR takes the original path, Aztec/PDF417/Code 128
    /// are CoreImage siblings, EAN-13/EAN-8 go through the hand-rolled encoder.
    static func image(payload: String, design: DesignOptions) -> UIImage? {
        switch design.symbology {
        case .qr:
            return renderQR(payload: payload, design: design)
        case .aztec, .pdf417, .code128:
            return renderCoreImageCode(payload: payload, design: design)
        case .ean13, .ean8:
            return renderEAN(payload: payload, design: design)
        }
    }

    private static func renderQR(payload: String, design: DesignOptions) -> UIImage? {
        // Any module styling switches to the custom path renderer; plain
        // square codes keep the pixel-quantized CI upscale (fastest, sharpest).
        guard design.isPlainStyle else {
            return StyledQRRenderer.image(payload: payload, design: design)
        }
        guard let qr = cgQR(payload: payload, design: design) else { return nil }
        let size = CGFloat(design.exportSize)
        // Pixel quantization: the CI symbol is exactly one pixel per module,
        // so render each module as an INTEGER number of pixels. Fractional
        // module widths are what smeared edges before. Leftover space splits
        // evenly and simply becomes extra quiet zone.
        let symbol = qr.width
        let modulePx = (size / CGFloat(symbol + 2 * design.quietModules)).rounded(.down)
        let codeW = modulePx * CGFloat(symbol)
        let margin = ((size - codeW) / 2).rounded()
        let codeRect = CGRect(x: margin, y: margin, width: codeW, height: codeW)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // pixel-exact; the canvas is already device-independent
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let base = renderer.image { ctx in
            // The CI symbol is a tiny bitmap (e.g. 29×29 modules) — upscale
            // nearest-neighbor or the modules smear into grey mush.
            ctx.cgContext.interpolationQuality = .none
            design.bgUIColor.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIImage(cgImage: qr).draw(in: codeRect.integral)

            if let logoData = design.logoPNG, let logo = UIImage(data: logoData) {
                ctx.cgContext.interpolationQuality = .high // logos should stay smooth
                drawLogo(logo, in: ctx.cgContext, codeRect: codeRect.integral, design: design)
            }
        }
        guard design.ctaEnabled else { return base }
        return addContextBand(to: base, payload: payload, design: design)
    }

    /// Aztec, PDF417 and Code 128 — same CoreImage family as QR, one filter
    /// swap each. Aspect ratio is preserved (PDF417 and Code 128 are wide);
    /// the logo composite stays limited to 2D symbologies with real EC.
    private static func renderCoreImageCode(payload: String, design: DesignOptions) -> UIImage? {
        let filterName: String
        switch design.symbology {
        case .aztec: filterName = "CIAztecCodeGenerator"
        case .pdf417: filterName = "CIPDF417BarcodeGenerator"
        case .code128: filterName = "CICode128BarcodeGenerator"
        default: return nil
        }
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        guard var output = filter.outputImage else { return nil }

        if let colorize = CIFilter(name: "CIFalseColor") {
            colorize.setValue(output, forKey: kCIInputImageKey)
            colorize.setValue(CIColor(color: design.fgUIColor), forKey: "inputColor0")
            colorize.setValue(CIColor(color: design.bgUIColor), forKey: "inputColor1")
            if let colored = colorize.outputImage { output = colored }
        }
        guard let cg = ciContext.createCGImage(output, from: output.extent) else { return nil }

        let size = CGFloat(design.exportSize)
        // One module size for BOTH axes. The earlier version clamped an
        // over-tall code by recomputing the width from the aspect ratio, which
        // left the bars on fractional pixel boundaries and let anti-aliasing
        // grey them — the exact failure this quantisation exists to prevent.
        // Solving for the module size instead keeps every bar an integer
        // number of pixels wide.
        let symbolW = cg.width
        let symbolH = cg.height
        let quiet = CGFloat(design.quietModules)
        let modulePx = min((size / (CGFloat(symbolW) + 2 * quiet)).rounded(.down),
                           (size / (CGFloat(symbolH) + 2 * quiet)).rounded(.down))
        guard modulePx >= 1 else { return nil }
        let codeW = modulePx * CGFloat(symbolW)
        let codeH = modulePx * CGFloat(symbolH)
        let codeRect = CGRect(x: ((size - codeW) / 2).rounded(), y: ((size - codeH) / 2).rounded(),
                              width: codeW, height: codeH)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let base = renderer.image { ctx in
            // Same nearest-neighbor rule as QR: the CI output is a tiny
            // module bitmap, smooth upscaling would smear it.
            ctx.cgContext.interpolationQuality = .none
            design.bgUIColor.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIImage(cgImage: cg).draw(in: codeRect.integral)

            if design.symbology.carriesRichPayload,
               let logoData = design.logoPNG, let logo = UIImage(data: logoData) {
                ctx.cgContext.interpolationQuality = .high
                drawLogo(logo, in: ctx.cgContext, codeRect: codeRect.integral, design: design)
            }
        }
        guard design.ctaEnabled else { return base }
        return addContextBand(to: base, payload: payload, design: design)
    }

    /// EAN-13 / EAN-8 — bars from the hand-rolled module row, digits printed
    /// below in GS1 style. No logo, ever: occluding a linear code kills it.
    private static func renderEAN(payload: String, design: DesignOptions) -> UIImage? {
        guard let modules = EANEncoder.modules(payload, kind: design.symbology),
              let digits = EANEncoder.normalized(payload, kind: design.symbology) else { return nil }

        let size = CGFloat(design.exportSize)
        // Integer module width here too — fractional bars anti-alias grey.
        let totalModules = modules.count + 2 * design.quietModules
        let modulePx = (size / CGFloat(totalModules)).rounded(.down)
        let codeW = modulePx * CGFloat(modules.count)
        let barsH = codeW * 0.52
        let digitsH = modulePx * 7
        let codeH = barsH + digitsH + modulePx * 2
        let origin = CGPoint(x: ((size - codeW) / 2).rounded(), y: ((size - codeH) / 2).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { ctx in
            design.bgUIColor.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            design.fgUIColor.setFill()
            for (i, bit) in modules.enumerated() where bit == "1" {
                ctx.fill(CGRect(x: origin.x + CGFloat(i) * modulePx,
                                y: origin.y,
                                width: modulePx,
                                height: barsH))
            }

            let font = UIFont.monospacedDigitSystemFont(ofSize: digitsH, weight: .regular)
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: design.fgUIColor]
            let textSize = (digits as NSString).size(withAttributes: attr)
            (digits as NSString).draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: origin.y + barsH + modulePx * 2),
                withAttributes: attr
            )
        }
    }

    static func pngData(payload: String, design: DesignOptions) -> Data? {
        image(payload: payload, design: design)?.pngData()
    }

    /// PDF export: the code rasterised at 2048px on a print-sized page.
    /// The page previously matched the image at 2048×2048 points, about 28
    /// inches square, which every print dialog then had to scale down. 612pt
    /// (8.5") square suits labels and posters, and the aspect ratio is
    /// preserved so a Context Band still fits.
    static func pdfData(payload: String, design: DesignOptions) -> Data? {
        var hiRes = design
        hiRes.exportSize = 2048
        guard let img = image(payload: payload, design: hiRes) else { return nil }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 612)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let inset = pageRect.insetBy(dx: 36, dy: 36)
            let scale = min(inset.width / img.size.width, inset.height / img.size.height)
            let drawRect = CGRect(x: inset.midX - img.size.width * scale / 2,
                                  y: inset.midY - img.size.height * scale / 2,
                                  width: img.size.width * scale,
                                  height: img.size.height * scale)
            img.draw(in: drawRect)
        }
    }

    /// Destination label shown under the code in the Context Band — the trust
    /// layer: people see where the code leads before they scan it.
    /// Human-readable destination for the context band. MUST be
    /// payload-type-aware: the band is printed under the code on stickers
    /// and posters, so it may never leak secrets (Wi-Fi passwords) or
    /// personal data beyond what the code type itself advertises.
    static func destinationLabel(payload: String) -> String {
        if let host = URL(string: payload)?.host, !host.isEmpty {
            return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        }
        if payload.hasPrefix("WIFI:") {
            // "WIFI:T:WPA;S:CafeGuest;P:hunter2;;" — the SSID only, NEVER the
            // P: password field.
            if let ssid = wifiField("S", in: payload), !ssid.isEmpty { return "Wi-Fi: \(ssid)" }
            return "Wi-Fi network"
        }
        if payload.contains("BEGIN:VCARD") {
            for line in payload.components(separatedBy: .newlines) where line.hasPrefix("FN:") {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
            return "Contact card"
        }
        if payload.hasPrefix("bitcoin:") {
            let address = String(payload.dropFirst("bitcoin:".count).prefix(while: { $0 != "?" }))
            return address.count > 18 ? "Bitcoin: \(address.prefix(10))…\(address.suffix(6))" : "Bitcoin: \(address)"
        }
        if payload.hasPrefix("tel:") { return String(payload.dropFirst(4)) }
        if payload.hasPrefix("mailto:") {
            return String(payload.dropFirst(7).prefix(while: { $0 != "?" }))
        }
        if payload.hasPrefix("sms:") || payload.hasPrefix("SMSTO:") {
            let number = payload.components(separatedBy: ":").dropFirst().first ?? ""
            return "SMS: \(number)"
        }
        if payload.hasPrefix("geo:") { return "Location: \(payload.dropFirst(4))" }
        if payload.hasPrefix("BEGIN:VEVENT") || payload.hasPrefix("BEGIN:VCALENDAR") {
            for line in payload.components(separatedBy: .newlines) where line.hasPrefix("SUMMARY:") {
                return "Event: \(line.dropFirst(8))"
            }
            return "Calendar event"
        }
        let first = payload.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        return first.count > 42 ? "\(first.prefix(42))…" : first
    }

    /// Extracts a field from a WIFI: payload, honoring backslash-escaped
    /// separators (\; \: \\).
    private static func wifiField(_ key: String, in payload: String) -> String? {
        let body = String(payload.dropFirst(5)) // after "WIFI:"
        var fields: [String] = []
        var current = ""
        var escaped = false
        for ch in body {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == ";" { fields.append(current); current = ""; continue }
            current.append(ch)
        }
        fields.append(current)
        for field in fields where field.hasPrefix("\(key):") {
            return String(field.dropFirst(2))
        }
        return nil
    }

    // MARK: - Internals

    private static func cgQR(payload: String, design: DesignOptions) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue(design.errorLevel.rawValue, forKey: "inputCorrectionLevel")
        guard var output = filter.outputImage else { return nil }

        // Recolor the 1-bit symbol to the design's palette.
        if let colorize = CIFilter(name: "CIFalseColor") {
            colorize.setValue(output, forKey: kCIInputImageKey)
            colorize.setValue(CIColor(color: design.fgUIColor), forKey: "inputColor0")
            colorize.setValue(CIColor(color: design.bgUIColor), forKey: "inputColor1")
            if let colored = colorize.outputImage { output = colored }
        }
        return ciContext.createCGImage(output, from: output.extent)
    }

    /// Shared with StyledQRRenderer deliberately: both renderers must compose
    /// the logo identically, and this pair of functions used to exist twice —
    /// the copies had already drifted once (the Context Band's scale bug).
    static func drawLogo(_ logo: UIImage, in ctx: CGContext, codeRect: CGRect, design: DesignOptions) {
        let side = codeRect.width * CGFloat(design.logoScale)
        let pad = side * 0.14
        let box = CGRect(
            x: codeRect.midX - side / 2 - pad,
            y: codeRect.midY - side / 2 - pad,
            width: side + 2 * pad,
            height: side + 2 * pad
        )
        // White knockout behind the logo so modules never touch it.
        design.bgUIColor.setFill()
        let path = UIBezierPath(roundedRect: box, cornerRadius: box.width * 0.22)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        logo.draw(in: box.insetBy(dx: pad, dy: pad))
    }

    static func addContextBand(to base: UIImage, payload: String, design: DesignOptions) -> UIImage {
        let w = base.size.width
        let band = (w * 0.24).rounded()
        // scale = 1 is load-bearing: `base` is a scale-1.0 image whose size
        // IS pixels. A default renderer uses UIScreen.scale (3×), resampling
        // the code up 3× with smooth interpolation — blurring exactly the
        // crisp module edges the pixel quantisation preserved, and tripling
        // the exported file size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: base.size.height + band), format: format)
        return renderer.image { ctx in
            design.bgUIColor.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: base.size.height + band))
            base.draw(at: .zero)

            design.fgUIColor.setFill()
            ctx.fill(CGRect(x: 0, y: base.size.height, width: w, height: band))

            let cta = design.ctaText.trimmingCharacters(in: .whitespaces).isEmpty ? "Scan me" : design.ctaText
            let ctaFont = UIFont.systemFont(ofSize: band * 0.34, weight: .bold)
            let ctaAttr: [NSAttributedString.Key: Any] = [.font: ctaFont, .foregroundColor: design.bgUIColor]
            let ctaSize = (cta as NSString).size(withAttributes: ctaAttr)
            (cta as NSString).draw(
                at: CGPoint(x: (w - ctaSize.width) / 2, y: base.size.height + band * 0.14),
                withAttributes: ctaAttr
            )

            let dest = destinationLabel(payload: payload)
            if !dest.isEmpty {
                let destFont = UIFont.monospacedSystemFont(ofSize: band * 0.2, weight: .regular)
                let destAttr: [NSAttributedString.Key: Any] = [
                    .font: destFont,
                    .foregroundColor: design.bgUIColor.withAlphaComponent(0.75),
                ]
                let destSize = (dest as NSString).size(withAttributes: destAttr)
                (dest as NSString).draw(
                    at: CGPoint(x: (w - destSize.width) / 2, y: base.size.height + band * 0.62),
                    withAttributes: destAttr
                )
            }
        }
    }

    // MARK: - SVG

    /// Vector export for QR codes, serialised from the same module path the
    /// raster renderer fills — so the two describe the same symbol, styled
    /// shapes included.
    ///
    /// Linear and stacked symbologies are raster-only: they come from CoreImage
    /// bitmaps with no module geometry to serialise, so this returns nil for
    /// them rather than emitting an approximation.
    static func svg(payload: String, design: DesignOptions) -> String? {
        guard design.symbology == .qr,
              let geometry = StyledQRRenderer.geometry(payload: payload, design: design) else { return nil }

        let size = CGFloat(design.exportSize)
        let band = design.ctaEnabled && !design.transparentBg ? (size * 0.24).rounded() : 0
        let height = size + band

        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(number(size))" height="\(number(height))" viewBox="0 0 \(number(size)) \(number(height))">

        """
        if design.gradientEnabled {
            let angle = design.gradientRotation * .pi / 180
            out += """
              <defs>
                <linearGradient id="modules" x1="\(number(0.5 - cos(angle) / 2))" y1="\(number(0.5 - sin(angle) / 2))" x2="\(number(0.5 + cos(angle) / 2))" y2="\(number(0.5 + sin(angle) / 2))">
                  <stop offset="0" stop-color="\(design.fgHex)"/>
                  <stop offset="1" stop-color="\(design.gradientColor2Hex)"/>
                </linearGradient>
              </defs>

            """
        }
        if !design.transparentBg {
            out += "  <rect width=\"\(number(size))\" height=\"\(number(height))\" fill=\"\(design.bgHex)\"/>\n"
        }
        let fill = design.gradientEnabled ? "url(#modules)" : design.fgHex
        out += "  <path d=\"\(svgPathData(geometry.path))\" fill=\"\(fill)\" fill-rule=\"evenodd\"/>\n"

        if let logoData = design.logoPNG {
            // Same knockout box as the raster renderer: the logo covers the
            // modules behind it, padded so nothing touches the edge.
            let side = geometry.codeRect.width * CGFloat(design.logoScale)
            let pad = side * 0.14
            let box = CGRect(x: geometry.codeRect.midX - side / 2 - pad,
                             y: geometry.codeRect.midY - side / 2 - pad,
                             width: side + 2 * pad, height: side + 2 * pad)
            out += "  <rect x=\"\(number(box.minX))\" y=\"\(number(box.minY))\" width=\"\(number(box.width))\" height=\"\(number(box.height))\" rx=\"\(number(box.width * 0.22))\" fill=\"\(design.bgHex)\"/>\n"
            out += "  <image x=\"\(number(box.minX + pad))\" y=\"\(number(box.minY + pad))\" width=\"\(number(side))\" height=\"\(number(side))\" href=\"data:image/png;base64,\(logoData.base64EncodedString())\"/>\n"
        }

        if band > 0 {
            // y is a text BASELINE in SVG and the top edge in CoreGraphics, so
            // these offsets sit the text by eye rather than by shared maths.
            let cta = design.ctaText.trimmingCharacters(in: .whitespaces).isEmpty ? "Scan me" : design.ctaText
            let dest = destinationLabel(payload: payload)
            out += "  <g font-family=\"-apple-system, Helvetica, Arial, sans-serif\">\n"
            out += "    <rect y=\"\(number(size))\" width=\"\(number(size))\" height=\"\(number(band))\" fill=\"\(design.fgHex)\"/>\n"
            out += "    <text x=\"\(number(size / 2))\" y=\"\(number(size + band * 0.42))\" font-size=\"\(number(band * 0.34))\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"\(design.bgHex)\">\(xmlEscaped(cta))</text>\n"
            if !dest.isEmpty {
                out += "    <text x=\"\(number(size / 2))\" y=\"\(number(size + band * 0.82))\" font-size=\"\(number(band * 0.2))\" font-family=\"ui-monospace, Menlo, monospace\" text-anchor=\"middle\" fill=\"\(design.bgHex)\" fill-opacity=\"0.75\">\(xmlEscaped(dest))</text>\n"
            }
            out += "  </g>\n"
        }

        out += "</svg>\n"
        return out
    }

    /// Serialises a CGPath to SVG path data. `applyWithBlock` reports the path
    /// as it was built, curves included, so no geometry is approximated here.
    private static func svgPathData(_ path: CGPath) -> String {
        var data = ""
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                data += "M\(number(points[0].x)) \(number(points[0].y))"
            case .addLineToPoint:
                data += "L\(number(points[0].x)) \(number(points[0].y))"
            case .addQuadCurveToPoint:
                data += "Q\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y))"
            case .addCurveToPoint:
                data += "C\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y)) \(number(points[2].x)) \(number(points[2].y))"
            case .closeSubpath:
                data += "Z"
            @unknown default:
                break
            }
        }
        return data
    }

    /// Two decimals at most, without trailing zeros: SVG files stay readable and
    /// the numbers stay short.
    private static func number(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.2f", rounded)
    }

    private static func xmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

extension DesignOptions {
    var fgUIColor: UIColor { UIColor(hex: fgHex) }
    var bgUIColor: UIColor { UIColor(hex: bgHex) }
}

extension UIColor {
    convenience init(hex: String) {
        let c = Scanability.rgb(hex: hex)
        self.init(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    var hexString: String {
        // ColorPicker hands us extended-sRGB; a Display P3 red arrives as
        // r ≈ 1.09 → Int(1.09×255) = 278 → "%02X" = "116" → "#1160000" —
        // a bright red silently parsing as near-black downstream. Convert
        // to the sRGB space first, then clamp and ROUND (Int() truncates,
        // drifting in-gamut colors on every picker round-trip).
        let target = CGColorSpace(name: CGColorSpace.sRGB)!
        let srgb: UIColor
        if let converted = cgColor.converted(to: target, intent: .defaultIntent, options: nil) {
            srgb = UIColor(cgColor: converted)
        } else {
            srgb = self
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: nil)
        let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
