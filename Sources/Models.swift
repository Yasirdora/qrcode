import Foundation

/// Every payload family the app can encode. Mirrors the web studio 1:1 so a
/// user moving between the two finds the same vocabulary.
enum ContentType: String, Codable, CaseIterable, Identifiable {
    case url, text, wifi, vcard, sms, phone, geo, event, crypto, whatsapp, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .url: "URL"
        case .text: "Text"
        case .wifi: "Wi-Fi"
        case .vcard: "vCard"
        case .sms: "SMS"
        case .phone: "Phone"
        case .geo: "Geo"
        case .event: "Event"
        case .crypto: "Crypto"
        case .whatsapp: "WhatsApp"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .url: "link"
        case .text: "text.alignleft"
        case .wifi: "wifi"
        case .vcard: "person.crop.rectangle"
        case .sms: "message"
        case .phone: "phone"
        case .geo: "mappin"
        case .event: "calendar"
        case .crypto: "bitcoinsign.circle"
        case .whatsapp: "bubble.left.and.bubble.right"
        case .custom: "curlybraces"
        }
    }
}

/// Barcode symbologies the studio can write: Tier 1 (CoreImage-native) plus
/// Tier 2 (hand-rolled EAN). Reading covers a superset via AVFoundation —
/// including Data Matrix, which we decode but never generate.
enum Symbology: String, Codable, CaseIterable, Identifiable {
    case qr, aztec, pdf417, code128, ean13, ean8

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: "QR Code"
        case .aztec: "Aztec"
        case .pdf417: "PDF417"
        case .code128: "Code 128"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        }
    }

    /// 2D/stacked codes carry any structured payload; linear codes are
    /// constrained to a single raw value.
    var carriesRichPayload: Bool {
        switch self {
        case .qr, .aztec, .pdf417: true
        case .code128, .ean13, .ean8: false
        }
    }

    /// Hint shown in the constrained linear-code field.
    var valueHint: String {
        switch self {
        case .code128: "ASCII text, up to ~40 characters"
        case .ean13: "12 or 13 digits — check digit verified"
        case .ean8: "7 or 8 digits — check digit verified"
        case .qr, .aztec, .pdf417: ""
        }
    }
}

struct WiFiFields: Codable, Equatable {
    var ssid = ""
    var password = ""
    var encryption = "WPA" // WPA | WEP | nopass
    var hidden = false
}

struct VCardFields: Codable, Equatable {
    var firstName = ""
    var lastName = ""
    var org = ""
    var title = ""
    var phone = ""
    var email = ""
    var url = ""
}

struct EventFields: Codable, Equatable {
    var title = ""
    var location = ""
    var start: Date?
    var end: Date?
}

/// All user input for a code. Codable so history entries persist the full
/// editing context, not just the rendered payload.
struct ContentState: Codable, Equatable {
    var type: ContentType = .url
    var url = "https://github.com"
    var text = ""
    var wifi = WiFiFields()
    var vcard = VCardFields()
    var smsNumber = ""
    var smsMessage = ""
    var phoneNumber = ""
    var geoLat = ""
    var geoLng = ""
    var event = EventFields()
    var cryptoAddress = ""
    var cryptoAmount = ""
    var whatsappNumber = ""
    var whatsappMessage = ""
    var customText = ""
    /// Raw value for linear symbologies (Code 128 / EAN) — the only payload
    /// those formats can carry.
    var barcodeValue = ""

    /// decodeIfPresent everywhere: history entries written before a field
    /// existed must survive every future schema bump.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(ContentType.self, forKey: .type) ?? .url
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? "https://github.com"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        wifi = try c.decodeIfPresent(WiFiFields.self, forKey: .wifi) ?? WiFiFields()
        vcard = try c.decodeIfPresent(VCardFields.self, forKey: .vcard) ?? VCardFields()
        smsNumber = try c.decodeIfPresent(String.self, forKey: .smsNumber) ?? ""
        smsMessage = try c.decodeIfPresent(String.self, forKey: .smsMessage) ?? ""
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        geoLat = try c.decodeIfPresent(String.self, forKey: .geoLat) ?? ""
        geoLng = try c.decodeIfPresent(String.self, forKey: .geoLng) ?? ""
        event = try c.decodeIfPresent(EventFields.self, forKey: .event) ?? EventFields()
        cryptoAddress = try c.decodeIfPresent(String.self, forKey: .cryptoAddress) ?? ""
        cryptoAmount = try c.decodeIfPresent(String.self, forKey: .cryptoAmount) ?? ""
        whatsappNumber = try c.decodeIfPresent(String.self, forKey: .whatsappNumber) ?? ""
        whatsappMessage = try c.decodeIfPresent(String.self, forKey: .whatsappMessage) ?? ""
        customText = try c.decodeIfPresent(String.self, forKey: .customText) ?? ""
        barcodeValue = try c.decodeIfPresent(String.self, forKey: .barcodeValue) ?? ""
    }

    init() {}
}

/// Module (dot) shapes — mirrors the web studio's qr-code-styling vocabulary
/// so both apps speak one design language.
enum DotType: String, Codable, CaseIterable, Identifiable {
    // Deliberately small vocabulary: square, dots, rounded square, fluid.
    // (Order is gallery order.)
    case square, dots, rounded, fluid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: "Square"
        case .dots: "Dots"
        case .rounded: "Rounded Square"
        case .fluid: "Fluid"
        }
    }

    /// Legacy designs saved with retired styles (classy, classyRounded,
    /// extraRounded) must not break decoding — they migrate to rounded,
    /// the closest surviving shape.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "square": self = .square
        case "dots": self = .dots
        case "fluid": self = .fluid
        default: self = .rounded
        }
    }
}

/// Finder-frame ("eye") shapes.
enum CornerSquareType: String, Codable, CaseIterable, Identifiable {
    case square, extraRounded, dot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: "Square"
        case .extraRounded: "Rounded"
        case .dot: "Circle"
        }
    }
}

/// Finder-dot shapes.
enum CornerDotType: String, Codable, CaseIterable, Identifiable {
    case square, dot
    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: "Square"
        case .dot: "Circle"
        }
    }
}

enum ErrorLevel: String, Codable, CaseIterable, Identifiable {
    case l = "L", m = "M", q = "Q", h = "H"
    var id: String { rawValue }
    /// Approximate share of codewords the level can recover.
    var recoveryPercent: Int {
        switch self {
        case .l: 7
        case .m: 15
        case .q: 25
        case .h: 30
        }
    }
}

/// Visual settings. Colors travel as hex strings so the model layer never
/// imports SwiftUI — the same rule as their `ProgressLogic` purity.
struct DesignOptions: Codable, Equatable {
    var symbology: Symbology = .qr
    var fgHex = "#111827"
    var bgHex = "#FFFFFF"
    var errorLevel: ErrorLevel = .q
    /// Quiet zone in modules; ISO/IEC 18004 requires >= 4.
    var quietModules = 4
    /// Raster export edge length in px.
    var exportSize = 1024
    var ctaEnabled = false
    var ctaText = "Scan me"
    /// Center logo is stored as PNG data, embedded in history entries.
    var logoPNG: Data? = nil
    /// Logo scale as a fraction of code edge. The design sheet caps the
    /// slider at 0.35: the knockout box adds 14% of padding per side, so
    /// 0.35 already destroys ~20% of the symbol's area — past the point
    /// where even EC-H recovers it reliably.
    var logoScale = 0.28
    // MARK: Module styling (QR only — web-studio vocabulary)
    var dotType: DotType = .square
    var cornerSquareType: CornerSquareType = .square
    var cornerDotType: CornerDotType = .square
    var gradientEnabled = false
    var gradientColor2Hex = "#7C3AED"
    var gradientRotation = 45.0
    var transparentBg = false

    /// Plain square rendering uses the crisp CI upscale path; any styling
    /// switches to the custom module-by-module renderer.
    var isPlainStyle: Bool {
        dotType == .square && cornerSquareType == .square && cornerDotType == .square
            && !gradientEnabled && !transparentBg
    }

    /// Same forward-compatibility rule as ContentState.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbology = try c.decodeIfPresent(Symbology.self, forKey: .symbology) ?? .qr
        fgHex = try c.decodeIfPresent(String.self, forKey: .fgHex) ?? "#111827"
        bgHex = try c.decodeIfPresent(String.self, forKey: .bgHex) ?? "#FFFFFF"
        errorLevel = try c.decodeIfPresent(ErrorLevel.self, forKey: .errorLevel) ?? .q
        quietModules = try c.decodeIfPresent(Int.self, forKey: .quietModules) ?? 4
        exportSize = try c.decodeIfPresent(Int.self, forKey: .exportSize) ?? 1024
        ctaEnabled = try c.decodeIfPresent(Bool.self, forKey: .ctaEnabled) ?? false
        ctaText = try c.decodeIfPresent(String.self, forKey: .ctaText) ?? "Scan me"
        logoPNG = try c.decodeIfPresent(Data.self, forKey: .logoPNG)
        logoScale = try c.decodeIfPresent(Double.self, forKey: .logoScale) ?? 0.28
        dotType = try c.decodeIfPresent(DotType.self, forKey: .dotType) ?? .square
        cornerSquareType = try c.decodeIfPresent(CornerSquareType.self, forKey: .cornerSquareType) ?? .square
        cornerDotType = try c.decodeIfPresent(CornerDotType.self, forKey: .cornerDotType) ?? .square
        gradientEnabled = try c.decodeIfPresent(Bool.self, forKey: .gradientEnabled) ?? false
        gradientColor2Hex = try c.decodeIfPresent(String.self, forKey: .gradientColor2Hex) ?? "#7C3AED"
        gradientRotation = try c.decodeIfPresent(Double.self, forKey: .gradientRotation) ?? 45.0
        transparentBg = try c.decodeIfPresent(Bool.self, forKey: .transparentBg) ?? false
    }

    init() {}
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var content: ContentState
    var design: DesignOptions
}

/// Curated one-tap looks — the Watch-faces idiom: a whole design coherent
/// enough to ship in one tap. Every gradient end is tuned to stay above
/// the 4:1 scanner-contrast line; a unit test guards that guarantee.
enum DesignPreset: String, CaseIterable, Identifiable {
    case classic, inkDots, flow, ocean, sunset, forest, violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .inkDots: "Ink Dots"
        case .flow: "Flow"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .forest: "Forest"
        case .violet: "Violet"
        }
    }

    /// Applies the look. Only styling changes — the payload, logo, quiet
    /// zone and export size are the user's and stay untouched.
    func apply(to d: inout DesignOptions) {
        d.transparentBg = false
        d.bgHex = "#FFFFFF"
        switch self {
        case .classic:
            d.fgHex = "#111827"
            d.dotType = .square; d.cornerSquareType = .square; d.cornerDotType = .square
            d.gradientEnabled = false
        case .inkDots:
            d.fgHex = "#111827"
            d.dotType = .dots; d.cornerSquareType = .dot; d.cornerDotType = .dot
            d.gradientEnabled = false
        case .flow:
            d.fgHex = "#0F172A"
            d.dotType = .fluid; d.cornerSquareType = .extraRounded; d.cornerDotType = .dot
            d.gradientEnabled = false
        case .ocean:
            d.fgHex = "#0C4A6E"; d.gradientColor2Hex = "#0369A1"
            d.dotType = .rounded; d.cornerSquareType = .extraRounded; d.cornerDotType = .square
            d.gradientEnabled = true; d.gradientRotation = 45
        case .sunset:
            d.fgHex = "#9A3412"; d.gradientColor2Hex = "#BE123C"
            d.dotType = .rounded; d.cornerSquareType = .extraRounded; d.cornerDotType = .dot
            d.gradientEnabled = true; d.gradientRotation = 45
        case .forest:
            d.fgHex = "#14532D"; d.gradientColor2Hex = "#15803D"
            d.dotType = .rounded; d.cornerSquareType = .extraRounded; d.cornerDotType = .square
            d.gradientEnabled = true; d.gradientRotation = 90
        case .violet:
            d.fgHex = "#4C1D95"; d.gradientColor2Hex = "#7C3AED"
            d.dotType = .dots; d.cornerSquareType = .dot; d.cornerDotType = .dot
            d.gradientEnabled = true; d.gradientRotation = 45
        }
    }

    /// Whether the given design currently matches this preset's styling.
    func matches(_ d: DesignOptions) -> Bool {
        var reference = DesignOptions()
        apply(to: &reference)
        return d.dotType == reference.dotType
            && d.cornerSquareType == reference.cornerSquareType
            && d.cornerDotType == reference.cornerDotType
            && d.gradientEnabled == reference.gradientEnabled
            && d.fgHex.caseInsensitiveCompare(reference.fgHex) == .orderedSame
            && (!reference.gradientEnabled
                || d.gradientColor2Hex.caseInsensitiveCompare(reference.gradientColor2Hex) == .orderedSame)
    }
}
