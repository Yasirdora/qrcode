import Foundation

/// Real-time "will this actually scan?" engine — the feature that separates
/// this studio from every generator that lets you ship an unscannable code.
///
/// Pure Foundation for the same reason as PayloadBuilder: unit tests pin the
/// scoring rules without a simulator.
enum Scanability {

    enum Status: String, Codable {
        case pass, warn, fail
        var points: Double {
            switch self {
            case .pass: 1
            case .warn: 0.5
            case .fail: 0
            }
        }
    }

    struct Check: Codable, Identifiable {
        var id: String
        var label: String
        var status: Status
        var detail: String
        var weight: Double
    }

    struct Report: Codable {
        var score: Int // 0–100
        var grade: String
        var checks: [Check]
    }

    static func score(payload: String, design d: DesignOptions) -> Report {
        var checks: [Check] = []
        let bytes = payload.utf8.count

        // 1. Contrast — the #1 cause of unscannable styled codes. With a
        // gradient, the weakest end of the blend is what scanners face.
        var ratio = contrastRatio(fg: d.fgHex, bg: d.bgHex)
        if d.symbology == .qr && d.gradientEnabled {
            ratio = min(ratio, contrastRatio(fg: d.gradientColor2Hex, bg: d.bgHex))
        }
        let ratioText = String(format: "%.1f", ratio)
        checks.append(Check(
            id: "contrast",
            label: "Foreground / background contrast",
            status: ratio >= 4 ? .pass : ratio >= 2.5 ? .warn : .fail,
            detail: ratio >= 4
                ? "Contrast ratio \(ratioText):1 — scans fast in all lighting."
                : ratio >= 2.5
                    ? "Contrast ratio \(ratioText):1 — marginal. Darken the modules."
                    : "Contrast ratio \(ratioText):1 — most cameras will fail.",
            weight: 35
        ))

        // 2. Symbology-specific payload/structure checks.
        switch d.symbology {
        case .qr:
            // Payload density — dense symbols demand print size and steady hands.
            let version = PayloadBuilder.estimateVersion(bytes: bytes, ec: d.errorLevel)
            let modules = version <= 40 ? 17 + version * 4 : 177
            checks.append(Check(
                id: "density",
                label: "Symbol density",
                status: version <= 6 ? .pass : version <= 20 ? .warn : .fail,
                detail: version <= 6
                    ? "~Version \(version) (\(modules)×\(modules) modules). Crisp even at small print sizes."
                    : version <= 20
                        ? "~Version \(version) (\(modules)×\(modules) modules). Shorten the payload or print larger (≥ 3 cm)."
                        : version <= 40
                            ? "~Version \(version) (\(modules)×\(modules) modules). Very dense — reduce payload size."
                            : "Payload exceeds QR capacity at EC level \(d.errorLevel.rawValue).",
                weight: 25
            ))
            // Module styling — the web-studio vocabulary has a scan cost the
            // user deserves to see before they print 10,000 stickers.
            checks.append(styleCheck(design: d))
            checks.append(logoCheck(design: d, allowance: Double(d.errorLevel.recoveryPercent) / 100.0,
                                    allowanceLabel: "EC \(d.errorLevel.rawValue) tolerates ~\(d.errorLevel.recoveryPercent)%"))

        case .aztec, .pdf417:
            // Both carry built-in Reed-Solomon EC (~23% by convention); the
            // practical limit is print size, not capacity.
            checks.append(Check(
                id: "density",
                label: "Payload size",
                status: bytes <= 60 ? .pass : bytes <= 250 ? .warn : .fail,
                detail: bytes <= 60
                    ? "\(bytes) bytes — compact layers, crisp at small print sizes."
                    : bytes <= 250
                        ? "\(bytes) bytes — print large (≥ 3 cm) for reliable reads."
                        : "\(bytes) bytes — very dense for \(d.symbology.title); shorten the payload.",
                weight: 25
            ))
            checks.append(logoCheck(design: d, allowance: 0.23,
                                    allowanceLabel: "built-in Reed-Solomon EC tolerates ~23%"))

        case .code128:
            let printable = payload.allSatisfy { $0.isASCII && $0.asciiValue.map { $0 >= 32 && $0 < 127 } == true }
            checks.append(Check(
                id: "payload",
                label: "Code 128 payload",
                status: payload.isEmpty ? .warn
                    : !printable ? .fail
                    : bytes <= 24 ? .pass : bytes <= 40 ? .warn : .fail,
                detail: payload.isEmpty ? "No value yet — enter the code's content."
                    : !printable ? "Code 128 carries printable ASCII only — remove emoji/accented characters."
                    : bytes <= 24 ? "\(bytes) characters — short bars scan instantly, even with laser scanners."
                    : bytes <= 40 ? "\(bytes) characters — long bars demand wide labels; keep under ~40."
                    : "\(bytes) characters — too long to print reliably. Shorten it.",
                weight: 45
            ))

        case .ean13, .ean8:
            let valid = EANEncoder.normalized(payload, kind: d.symbology)
            checks.append(Check(
                id: "payload",
                label: "GS1 \(d.symbology.title) digits",
                status: payload.isEmpty ? .warn : valid != nil ? .pass : .fail,
                detail: payload.isEmpty
                    ? "No digits yet — \(d.symbology.valueHint.lowercased())."
                    : valid != nil
                        ? "Valid — GS1 check digit \(valid!.last!) verified. Scans at every retail terminal."
                        : "Needs \(d.symbology == .ean13 ? "12–13" : "7–8") digits with a valid GS1 check digit.",
                weight: 45
            ))
        }

        // 3. Quiet zone — the threshold depends on the symbology. Applying
        // the QR rule (ISO/IEC 18004: ≥4 modules) to retail linear codes
        // tells users a barcode is fine when it will fail at a POS scanner:
        // GS1 demands 11 modules left / 7 right on EAN-13 (≥7 on EAN-8),
        // and ISO/IEC 15417 demands 10 modules on Code 128.
        switch d.symbology {
        case .ean13:
            checks.append(Check(
                id: "quiet",
                label: "Quiet zone",
                status: d.quietModules >= 11 ? .pass : d.quietModules >= 7 ? .warn : .fail,
                detail: d.quietModules >= 11
                    ? "\(d.quietModules)-module quiet zone — meets the GS1 EAN-13 minimum (11 left / 7 right)."
                    : "GS1 requires 11 modules left of an EAN-13 (7 right). At \(d.quietModules), POS scanners may refuse it.",
                weight: 12
            ))
        case .ean8:
            checks.append(Check(
                id: "quiet",
                label: "Quiet zone",
                status: d.quietModules >= 7 ? .pass : d.quietModules >= 4 ? .warn : .fail,
                detail: d.quietModules >= 7
                    ? "\(d.quietModules)-module quiet zone — meets the GS1 EAN-8 minimum (7 each side)."
                    : "GS1 requires 7 modules each side of an EAN-8. At \(d.quietModules), POS scanners may refuse it.",
                weight: 12
            ))
        case .code128:
            checks.append(Check(
                id: "quiet",
                label: "Quiet zone",
                status: d.quietModules >= 10 ? .pass : d.quietModules >= 6 ? .warn : .fail,
                detail: d.quietModules >= 10
                    ? "\(d.quietModules)-module quiet zone — meets the ISO/IEC 15417 minimum (10 each side)."
                    : "Code 128 needs 10 quiet modules each side. At \(d.quietModules), laser scanners may miss the start/stop pattern.",
                weight: 12
            ))
        case .qr, .aztec, .pdf417:
            checks.append(Check(
                id: "quiet",
                label: "Quiet zone",
                status: d.quietModules >= 4 ? .pass : d.quietModules >= 2 ? .warn : .fail,
                detail: d.quietModules >= 4
                    ? "\(d.quietModules)-module quiet zone — meets the ISO 4-module minimum."
                    : "\(d.quietModules)-module quiet zone — ISO requires 4. Raise it in Design settings.",
                weight: 12
            ))
        }

        // 4. Context band nudge — trust layer, not a scan risk.
        checks.append(Check(
            id: "context",
            label: "Context band",
            status: .pass,
            detail: d.ctaEnabled
                ? "Context band on — scanners see the destination before they scan."
                : "Optional: add a context band so people know where this code leads.",
            weight: 8
        ))

        let total = checks.reduce(0) { $0 + $1.weight }
        let earned = checks.reduce(0) { $0 + $1.status.points * $1.weight }
        let score = Int((earned / total * 100).rounded())
        let grade = score >= 90 ? "Excellent" : score >= 70 ? "Good" : score >= 45 ? "Risky" : "Likely unscannable"
        return Report(score: score, grade: grade, checks: checks)
    }

    /// Module/eye shapes and transparent backgrounds trade ink for style.
    /// QR only — linear symbologies never take the styled path.
    private static func styleCheck(design d: DesignOptions) -> Check {
        let eyeNote = d.cornerSquareType == .dot
            ? " Circular eye frames read fine on modern phones."
            : ""
        if d.transparentBg {
            return Check(
                id: "style",
                label: "Module styling",
                status: .warn,
                detail: "Transparent background — the code borrows contrast from wherever it lands. Test on the real surface.",
                weight: 15
            )
        }
        switch d.dotType {
        case .square:
            return Check(
                id: "style",
                label: "Module styling",
                status: .pass,
                detail: "Square modules — maximum ink per module, the most forgiving shape.\(eyeNote)",
                weight: 15
            )
        case .rounded:
            return Check(
                id: "style",
                label: "Module styling",
                status: .pass,
                detail: "Rounded modules — negligible area loss; scans like square on any modern phone.\(eyeNote)",
                weight: 15
            )
        case .fluid:
            return Check(
                id: "style",
                label: "Module styling",
                status: .pass,
                detail: "Fluid modules merge with their neighbors — full module coverage is preserved, so scanability matches rounded.\(eyeNote)",
                weight: 15
            )
        case .dots:
            return Check(
                id: "style",
                label: "Module styling",
                status: .warn,
                detail: "Dot modules shed ~21% of the ink area — modern phones cope, budget scanners may not.\(eyeNote)",
                weight: 15
            )
        case .extraRounded:
            return Check(
                id: "style",
                label: "Module styling",
                status: .pass,
                detail: "Smooth modules round only the corners that face empty space, so runs keep their edges.\(eyeNote)",
                weight: 15
            )
        case .classy:
            return Check(
                id: "style",
                label: "Module styling",
                status: .pass,
                detail: "Classy modules stay square wherever a neighbor touches them and round only at the ends of a run.\(eyeNote)",
                weight: 15
            )
        case .classyRounded:
            return Check(
                id: "style",
                label: "Module styling",
                status: .warn,
                detail: "Leaf modules round their free corners at the full module width, which costs more ink at the end of every run than rounded does.\(eyeNote)",
                weight: 15
            )
        }
    }

    /// Logo occlusion vs error-correction allowance — shared by the 2D
    /// symbologies; linear codes never reach this (no logo is rendered).
    private static func logoCheck(design d: DesignOptions, allowance: Double, allowanceLabel: String) -> Check {
        if d.logoPNG != nil {
            // The renderer knocks out a box padded 14% on every side
            // (QRRenderer.drawLogo), so the destroyed area is (1.28·scale)² —
            // 64% MORE than the logo's own area. Scoring the logo alone told
            // users a dead code was "marginal".
            // Calibrated against RoundTripTests at EC-H: 0.35 scale (20%
            // occlusion) still decodes; 0.40 (26%) does not.
            let occlusion = pow(d.logoScale * 1.28, 2)
            let ocPct = Int((occlusion * 100).rounded())
            return Check(
                id: "logo",
                label: "Logo occlusion vs error correction",
                status: occlusion <= allowance * 0.7 ? .pass : occlusion <= allowance * 0.85 ? .warn : .fail,
                detail: occlusion <= allowance * 0.85
                    ? "Logo + clear-zone covers ~\(ocPct)% of the symbol; \(allowanceLabel)."
                    : "Logo + clear-zone covers ~\(ocPct)% — measured decode failure starts here. Shrink the logo or raise EC.",
                weight: 20
            )
        }
        return Check(
            id: "logo",
            label: "Logo occlusion",
            status: .pass,
            detail: "No logo embedded — full symbol area is machine-readable.",
            weight: 20
        )
    }

    /// WCAG relative-luminance contrast ratio between two #RRGGBB colors.
    static func contrastRatio(fg: String, bg: String) -> Double {
        let l1 = luminance(rgb(hex: fg))
        let l2 = luminance(rgb(hex: bg))
        let hi = max(l1, l2), lo = min(l1, l2)
        return (hi + 0.05) / (lo + 0.05)
    }

    static func rgb(hex: String) -> (r: Double, g: Double, b: Double) {
        var h = hex.replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard let n = UInt64(h, radix: 16) else { return (0, 0, 0) }
        return (
            Double((n >> 16) & 0xFF) / 255,
            Double((n >> 8) & 0xFF) / 255,
            Double(n & 0xFF) / 255
        )
    }

    private static func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func f(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
}
