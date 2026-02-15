import UIKit
import CoreImage

/// Custom module-level QR renderer — the iOS port of the web studio's
/// qr-code-styling vocabulary (dot shapes, eye shapes, gradients, transparent
/// backgrounds). Extracts the symbol matrix from CoreImage's generator, then
/// draws every module as a vector path, so styled output stays crisp at any
/// export size. Shape geometry is a close approximation of qr-code-styling's,
/// not a pixel-identical clone.
enum StyledQRRenderer {

    private static let ciContext = CIContext()

    // MARK: - Matrix extraction

    /// The QR symbol as a module grid (true = dark), one cell per module.
    ///
    /// CoreImage's generator pads its output (quiet-zone rows/columns), so
    /// the raw bitmap's corners are NOT the symbol's corners. We therefore
    /// crop to the dark bounding box — the finder rings are the outermost
    /// dark modules, so the crop lands exactly on the symbol — then check
    /// all four corners for finder blocks to detect and undo any mirror
    /// flip the bitmap read may have introduced.
    static func matrix(payload: String, ec: ErrorLevel) -> (grid: [Bool], size: Int)? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue(ec.rawValue, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let n = Int(output.extent.width)
        guard n > 0, let cg = ciContext.createCGImage(output, from: output.extent) else { return nil }

        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        guard let ctx = CGContext(
            data: &bytes, width: n, height: n,
            bitsPerComponent: 8, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var raw = [Bool](repeating: false, count: n * n)
        for i in 0..<n * n { raw[i] = bytes[i * 4] < 128 }

        // Crop to the dark bounding box (removes generator padding).
        var minR = n, maxR = -1, minC = n, maxC = -1
        for r in 0..<n {
            for c in 0..<n where raw[r * n + c] {
                minR = min(minR, r); maxR = max(maxR, r)
                minC = min(minC, c); maxC = max(maxC, c)
            }
        }
        guard maxR >= minR, maxC >= minC else { return nil }
        let h = maxR - minR + 1, w = maxC - minC + 1
        let s = max(h, w) // QR symbols are square; tolerate 1-px render slack
        var grid = [Bool](repeating: false, count: s * s)
        for r in 0..<s {
            for c in 0..<s {
                let sr = minR + r, sc = minC + c
                if sr <= maxR, sc <= maxC { grid[r * s + c] = raw[sr * n + sc] }
            }
        }

        // Mirror normalization. A bitmap read can flip the symbol; a mirrored
        // code is not standard and many readers reject it. Finders belong at
        // TL/TR/BL — if they sit at TL/BL/BR the grid is vertically flipped,
        // at TL/TR/BR horizontally flipped. (A 180° rotation — TR/BL/BR — is
        // left alone: rotated codes scan perfectly.)
        func finderAt(_ r: Int, _ c: Int) -> Bool { isFinderBlock(grid: grid, n: s, row: r, col: c) }
        let tl = finderAt(0, 0), tr = finderAt(0, s - 7)
        let bl = finderAt(s - 7, 0), br = finderAt(s - 7, s - 7)
        if tl && bl && br && !tr {
            for r in 0..<s / 2 {
                for c in 0..<s { grid.swapAt(r * s + c, (s - 1 - r) * s + c) }
            }
        } else if tl && tr && br && !bl {
            for r in 0..<s {
                for c in 0..<s / 2 { grid.swapAt(r * s + c, r * s + (s - 1 - c)) }
            }
        }
        return (grid, s)
    }

    // MARK: - Finder patterns

    /// A 7×7 block is a finder pattern if its ring corners and 3×3 center
    /// are dark while the inner ring's edge-centers are light. Orientation-
    /// proof: works regardless of how CoreImage flipped the bitmap.
    static func isFinderBlock(grid: [Bool], n: Int, row: Int, col: Int) -> Bool {
        guard row >= 0, col >= 0, row + 7 <= n, col + 7 <= n else { return false }
        func cell(_ r: Int, _ c: Int) -> Bool { grid[(row + r) * n + (col + c)] }
        for (r, c) in [(0, 0), (0, 6), (6, 0), (6, 6), (2, 2), (2, 4), (4, 2), (4, 4), (3, 3)] {
            guard cell(r, c) else { return false }
        }
        for (r, c) in [(1, 1), (1, 3), (1, 5), (3, 1), (3, 5), (5, 1), (5, 3), (5, 5)] {
            guard !cell(r, c) else { return false }
        }
        return true
    }

    /// Origins (row, col) of the finder blocks. All four corners are checked:
    /// after mirror normalization the canonical QR has three (TL/TR/BL), but
    /// a 180°-rotated symbol — which scans fine — puts them at TR/BL/BR.
    static func finderBlocks(grid: [Bool], n: Int) -> [(row: Int, col: Int)] {
        var blocks: [(Int, Int)] = []
        for (r, c) in [(0, 0), (0, n - 7), (n - 7, 0), (n - 7, n - 7)]
        where isFinderBlock(grid: grid, n: n, row: r, col: c) {
            blocks.append((r, c))
        }
        return blocks
    }

    // MARK: - Rendering

    static func image(payload: String, design: DesignOptions) -> UIImage? {
        guard let (grid, n) = matrix(payload: payload, ec: design.errorLevel) else { return nil }
        let size = CGFloat(design.exportSize)
        let modulePx = (size / CGFloat(n + 2 * design.quietModules)).rounded(.down)
        guard modulePx >= 1 else { return nil }
        let codeW = modulePx * CGFloat(n)
        let margin = ((size - codeW) / 2).rounded()
        let codeRect = CGRect(x: margin, y: margin, width: codeW, height: codeW)
        let finders = finderBlocks(grid: grid, n: n)

        // Every dark module becomes one subpath in a single path, so the fill
        // — solid or gradient — lands in exactly the same shape.
        let path = CGMutablePath()
        func cellRect(_ r: Int, _ c: Int) -> CGRect {
            CGRect(x: codeRect.minX + CGFloat(c) * modulePx,
                   y: codeRect.minY + CGFloat(r) * modulePx,
                   width: modulePx, height: modulePx)
        }
        func insideFinder(_ r: Int, _ c: Int) -> Bool {
            finders.contains { r >= $0.row && r < $0.row + 7 && c >= $0.col && c < $0.col + 7 }
        }

        // 1. Data/timing modules in the chosen dot style.
        for r in 0..<n {
            for c in 0..<n where grid[r * n + c] && !insideFinder(r, c) {
                if design.dotType == .fluid {
                    // Fluid modules are neighbor-aware: a corner only rounds
                    // when it faces empty space; corners between dark
                    // neighbors stay square so runs merge into one shape.
                    addFluidModule(to: path, rect: cellRect(r, c)) { dr, dc in
                        let rr = r + dr, cc = c + dc
                        guard rr >= 0, rr < n, cc >= 0, cc < n else { return false }
                        return grid[rr * n + cc] && !insideFinder(rr, cc)
                    }
                } else {
                    addModule(to: path, rect: cellRect(r, c), style: design.dotType)
                }
            }
        }
        // 2. The three eyes in the chosen corner styles.
        for f in finders {
            addEye(to: path, origin: cellRect(f.row, f.col).origin, modulePx: modulePx, design: design)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let base = renderer.image { ctx in
            let cg = ctx.cgContext
            if !design.transparentBg {
                design.bgUIColor.setFill()
                cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            }
            cg.addPath(path)
            // Even-odd: the eye frames are rings (outer minus inner), and
            // tiled data modules never overlap, so one rule serves both.
            cg.clip(using: .evenOdd)
            if design.gradientEnabled {
                let colors = [design.fgUIColor.cgColor, UIColor(hex: design.gradientColor2Hex).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    let angle = design.gradientRotation * .pi / 180
                    let start = CGPoint(x: codeRect.midX - cos(angle) * codeRect.width / 2,
                                        y: codeRect.midY - sin(angle) * codeRect.height / 2)
                    let end = CGPoint(x: codeRect.midX + cos(angle) * codeRect.width / 2,
                                      y: codeRect.midY + sin(angle) * codeRect.height / 2)
                    // Extend both ends: without this, the anti-diagonal corners
                    // (past the gradient line) get NO paint — the "teardrop" bug.
                    cg.drawLinearGradient(gradient, start: start, end: end,
                                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
            } else {
                design.fgUIColor.setFill()
                cg.fill(codeRect)
            }
            cg.resetClip()

            if let logoData = design.logoPNG, let logo = UIImage(data: logoData) {
                cg.interpolationQuality = .high
                drawLogo(logo, in: cg, codeRect: codeRect, design: design)
            }
        }
        guard design.ctaEnabled, !design.transparentBg else { return base }
        return addContextBand(to: base, payload: payload, design: design)
    }

    // MARK: - Module shapes

    private static func addModule(to path: CGMutablePath, rect: CGRect, style: DotType) {
        switch style {
        case .square:
            path.addRect(rect)
        case .rounded:
            // CoreGraphics rounded rects are UNDEFINED when the radius
            // exceeds half the rect's side — that produced teardrop modules.
            path.addRoundedRect(in: rect, cornerWidth: rect.width * 0.25, cornerHeight: rect.height * 0.25)
        case .dots:
            path.addEllipse(in: rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05))
        case .fluid:
            // Never reached — fluid needs neighbor context and is drawn by
            // addFluidModule in the module loop. Fallback keeps the switch
            // exhaustive without changing behavior.
            path.addRoundedRect(in: rect, cornerWidth: rect.width * 0.5, cornerHeight: rect.height * 0.5)
        }
    }

    /// One fluid module. `dark(dr, dc)` reports whether the module offset by
    /// (dr, dc) is also ink. A corner stays SQUARE whenever either neighbor
    /// touching it is dark — that's what makes runs fuse into one continuous
    /// rounded line. A corner rounds (to half the module size) only when both
    /// sides face empty space, so isolated modules become circles and run
    /// endings become capsule caps.
    private static func addFluidModule(to path: CGMutablePath, rect: CGRect, dark: (Int, Int) -> Bool) {
        let up = dark(-1, 0), down = dark(1, 0), left = dark(0, -1), right = dark(0, 1)
        let rad = rect.width * 0.5
        let tl: CGFloat = (up || left) ? 0 : rad
        let tr: CGFloat = (up || right) ? 0 : rad
        let br: CGFloat = (down || right) ? 0 : rad
        let bl: CGFloat = (down || left) ? 0 : rad
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                        startAngle: 0, endAngle: .pi / 2, clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                        startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                        startAngle: .pi, endAngle: -.pi / 2, clockwise: false)
        }
        path.closeSubpath()
    }

    // MARK: - Eyes

    private static func addEye(to path: CGMutablePath, origin: CGPoint, modulePx: CGFloat, design: DesignOptions) {
        let outer = CGRect(x: origin.x, y: origin.y, width: modulePx * 7, height: modulePx * 7)
        let inner = outer.insetBy(dx: modulePx, dy: modulePx)
        let center = outer.insetBy(dx: modulePx * 2, dy: modulePx * 2)

        // Frame ring (even-odd: outer shape minus 5×5 inner shape).
        switch design.cornerSquareType {
        case .square:
            path.addRect(outer)
            path.addRect(inner)
        case .extraRounded:
            path.addRoundedRect(in: outer, cornerWidth: modulePx * 2, cornerHeight: modulePx * 2)
            path.addRoundedRect(in: inner, cornerWidth: modulePx, cornerHeight: modulePx)
        case .dot:
            path.addEllipse(in: outer)
            path.addEllipse(in: inner)
        }
        // Center dot (3×3) — solid, even-odd is irrelevant for a single shape.
        switch design.cornerDotType {
        case .square:
            path.addRect(center)
        case .dot:
            path.addEllipse(in: center)
        }
    }

    // MARK: - Shared compositing (mirrors QRRenderer's logo/band)

    private static func drawLogo(_ logo: UIImage, in ctx: CGContext, codeRect: CGRect, design: DesignOptions) {
        let side = codeRect.width * CGFloat(design.logoScale)
        let pad = side * 0.14
        let box = CGRect(x: codeRect.midX - side / 2 - pad, y: codeRect.midY - side / 2 - pad,
                         width: side + 2 * pad, height: side + 2 * pad)
        design.bgUIColor.setFill()
        ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: box.width * 0.22).cgPath)
        ctx.fillPath()
        logo.draw(in: box.insetBy(dx: pad, dy: pad))
    }

    private static func addContextBand(to base: UIImage, payload: String, design: DesignOptions) -> UIImage {
        let w = base.size.width
        let band = (w * 0.24).rounded()
        // scale = 1 — see QRRenderer.addContextBand; a default 3× renderer
        // would blur the pixel-quantised modules and triple the file size.
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
            (cta as NSString).draw(at: CGPoint(x: (w - ctaSize.width) / 2, y: base.size.height + band * 0.14),
                                   withAttributes: ctaAttr)

            let dest = QRRenderer.destinationLabel(payload: payload)
            if !dest.isEmpty {
                let destFont = UIFont.monospacedSystemFont(ofSize: band * 0.2, weight: .regular)
                let destAttr: [NSAttributedString.Key: Any] = [
                    .font: destFont,
                    .foregroundColor: design.bgUIColor.withAlphaComponent(0.75),
                ]
                let destSize = (dest as NSString).size(withAttributes: destAttr)
                (dest as NSString).draw(at: CGPoint(x: (w - destSize.width) / 2, y: base.size.height + band * 0.62),
                                        withAttributes: destAttr)
            }
        }
    }
}
