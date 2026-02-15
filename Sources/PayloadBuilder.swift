import Foundation

/// Builds the raw string encoded into a QR symbol for each content type, plus
/// the human summary shown in lists and previews.
///
/// Pure Foundation — no SwiftUI, no UIKit — so the whole file is unit-testable
/// without a simulator (same rule as their ProgressLogic.swift).
enum PayloadBuilder {

    /// Symbology-aware entry point: linear codes can't carry structured
    /// payloads, so they read the raw barcode value instead of the mode form.
    static func payload(for c: ContentState, symbology: Symbology) -> String {
        guard symbology.carriesRichPayload else {
            return c.barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return payload(for: c)
    }

    static func payload(for c: ContentState) -> String {
        switch c.type {
        case .url:
            let u = c.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !u.isEmpty else { return "" }
            // Accept any URI scheme (https:, mailto:, tel:, yourapp:…) —
            // only prepend https when the user typed a bare domain.
            return u.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil
                ? u : "https://\(u)"

        case .text:
            return c.text

        case .wifi:
            guard !c.wifi.ssid.isEmpty else { return "" }
            var out = "WIFI:T:\(c.wifi.encryption);S:\(escapeWiFi(c.wifi.ssid));P:\(escapeWiFi(c.wifi.password));"
            if c.wifi.hidden { out += "H:true;" }
            return out + ";"

        case .vcard:
            let v = c.vcard
            guard !(v.firstName.isEmpty && v.lastName.isEmpty && v.phone.isEmpty && v.email.isEmpty) else { return "" }
            var lines = [
                "BEGIN:VCARD",
                "VERSION:3.0",
                "N:\(escapeVCard(v.lastName));\(escapeVCard(v.firstName));;;",
                "FN:\(escapeVCard("\(v.firstName) \(v.lastName)".trimmingCharacters(in: .whitespaces)))",
            ]
            if !v.org.isEmpty { lines.append("ORG:\(escapeVCard(v.org))") }
            if !v.title.isEmpty { lines.append("TITLE:\(escapeVCard(v.title))") }
            if !v.phone.isEmpty { lines.append("TEL;TYPE=CELL:\(v.phone)") }
            if !v.email.isEmpty { lines.append("EMAIL:\(v.email)") }
            if !v.url.isEmpty { lines.append("URL:\(v.url)") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\n")

        case .sms:
            guard !c.smsNumber.isEmpty else { return "" }
            var out = "sms:\(c.smsNumber)"
            if !c.smsMessage.isEmpty {
                out += "?body=\(c.smsMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c.smsMessage)"
            }
            return out

        case .phone:
            return c.phoneNumber.isEmpty ? "" : "tel:\(c.phoneNumber)"

        case .geo:
            guard !c.geoLat.isEmpty, !c.geoLng.isEmpty else { return "" }
            return "geo:\(c.geoLat),\(c.geoLng)"

        case .event:
            let e = c.event
            guard !e.title.isEmpty, let start = e.start else { return "" }
            var lines = ["BEGIN:VEVENT", "SUMMARY:\(escapeVCard(e.title))", "DTSTART:\(utcStamp(start))"]
            if let end = e.end { lines.append("DTEND:\(utcStamp(end))") }
            if !e.location.isEmpty { lines.append("LOCATION:\(escapeVCard(e.location))") }
            lines.append("END:VEVENT")
            return lines.joined(separator: "\n")

        case .crypto:
            guard !c.cryptoAddress.isEmpty else { return "" }
            return "bitcoin:\(c.cryptoAddress)\(c.cryptoAmount.isEmpty ? "" : "?amount=\(c.cryptoAmount)")"

        case .whatsapp:
            let digits = c.whatsappNumber.filter(\.isNumber)
            guard !digits.isEmpty else { return "" }
            var out = "https://wa.me/\(digits)"
            if !c.whatsappMessage.isEmpty {
                out += "?text=\(c.whatsappMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c.whatsappMessage)"
            }
            return out

        case .custom:
            return c.customText
        }
    }

    /// Human-friendly one-liner — shown anywhere the raw payload would be
    /// ugly or meaningless (WIFI:…, BEGIN:VCARD…).
    static func summarize(_ c: ContentState) -> String {
        switch c.type {
        case .url:
            if let host = URL(string: payload(for: c))?.host {
                return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            }
            return c.url.trimmingCharacters(in: .whitespaces).isEmpty ? "Link" : c.url
        case .text:
            let t = c.text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
            return t.isEmpty ? "Plain text" : String(t.prefix(40))
        case .wifi:
            return c.wifi.ssid.isEmpty ? "Wi-Fi network" : "Wi-Fi · \(c.wifi.ssid)"
        case .vcard:
            let name = "\(c.vcard.firstName) \(c.vcard.lastName)".trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? "Contact card" : "Contact · \(name)"
        case .sms:
            return c.smsNumber.isEmpty ? "Text message" : "SMS · \(c.smsNumber)"
        case .phone:
            return c.phoneNumber.isEmpty ? "Phone call" : "Call · \(c.phoneNumber)"
        case .geo:
            return (c.geoLat.isEmpty || c.geoLng.isEmpty) ? "Location" : "Location · \(c.geoLat), \(c.geoLng)"
        case .event:
            return c.event.title.isEmpty ? "Calendar event" : "Event · \(c.event.title)"
        case .crypto:
            return c.cryptoAddress.isEmpty ? "Bitcoin payment" : "Bitcoin · …\(c.cryptoAddress.suffix(8))"
        case .whatsapp:
            return c.whatsappNumber.isEmpty ? "WhatsApp chat" : "WhatsApp · \(c.whatsappNumber)"
        case .custom:
            let t = c.customText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
            return t.isEmpty ? "Custom payload" : "Custom · \(String(t.prefix(30)))"
        }
    }

    /// Approximate smallest QR version (1–40) needed for a byte payload at a
    /// given EC level, sampled from ISO/IEC 18004 byte-mode capacity tables.
    static func estimateVersion(bytes: Int, ec: ErrorLevel) -> Int {
        if bytes <= 0 { return 1 }
        let samples: [(version: Int, l: Int, m: Int, q: Int, h: Int)] = [
            (1, 17, 14, 11, 7),
            (2, 32, 26, 20, 14),
            (4, 78, 62, 46, 34),
            (6, 136, 108, 80, 60),
            (10, 271, 213, 151, 119),
            (14, 440, 348, 251, 198),
            (20, 861, 669, 482, 367),
            (26, 1274, 1000, 711, 548),
            (32, 1953, 1525, 1086, 831),
            (40, 2953, 2331, 1663, 1273),
        ]
        for s in samples {
            let cap: Int
            switch ec {
            case .l: cap = s.l
            case .m: cap = s.m
            case .q: cap = s.q
            case .h: cap = s.h
            }
            if bytes <= cap { return s.version }
        }
        return 41 // overflow
    }

    private static func escapeWiFi(_ s: String) -> String {
        s.replacingOccurrences(of: #"([\\;,:"'])"#, with: #"\\$1"#, options: .regularExpression)
    }

    private static func escapeVCard(_ s: String) -> String {
        s.replacingOccurrences(of: #"([\\;,])"#, with: #"\\$1"#, options: .regularExpression)
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func utcStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
