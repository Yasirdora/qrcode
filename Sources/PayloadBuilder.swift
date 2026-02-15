import Foundation
import CryptoKit

/// Builds the raw string encoded into a QR symbol for each content type, plus
/// the human summary shown in lists and previews.
///
/// Pure Foundation plus CryptoKit — no SwiftUI, no UIKit — so the whole file is
/// unit-testable without a simulator. CryptoKit is a first-party framework; it
/// is here only to verify Bitcoin address checksums before encoding them.
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
            // Every value is escaped, not only the name fields: a phone number
            // with an extension or a URL carrying a query string contains the
            // very separators (; and ,) that delimit vCard fields.
            if !v.phone.isEmpty { lines.append("TEL;TYPE=CELL:\(escapeVCard(v.phone))") }
            if !v.email.isEmpty { lines.append("EMAIL:\(escapeVCard(v.email))") }
            if !v.url.isEmpty { lines.append("URL:\(escapeVCard(v.url))") }
            lines.append("END:VCARD")
            // vCard 3.0 mandates CRLF; strict parsers reject LF-only records.
            return lines.joined(separator: "\r\n")

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
            // A bare VEVENT is tolerated by iOS but rejected by stricter
            // parsers, and several calendar clients want a UID before they
            // import. Both identifiers are derived from the event rather than
            // generated: the payload is recomputed on every render, so a
            // random UID would silently change the code between two exports.
            var lines = [
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "PRODID:-//Qr.Code//EN",
                "BEGIN:VEVENT",
                "UID:\(eventUID(e))",
                "DTSTAMP:\(utcStamp(start))",
                "SUMMARY:\(escapeVCard(e.title))",
                "DTSTART:\(utcStamp(start))",
            ]
            if let end = e.end { lines.append("DTEND:\(utcStamp(end))") }
            if !e.location.isEmpty { lines.append("LOCATION:\(escapeVCard(e.location))") }
            lines.append("END:VEVENT")
            lines.append("END:VCALENDAR")
            return lines.joined(separator: "\r\n")

        case .crypto:
            let address = c.cryptoAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            // A mistyped address is not recoverable, and the code is printed
            // before anyone can check it. Refuse to encode an address whose
            // checksum does not verify; an empty payload shows the "enter
            // content" state instead of a bad code.
            guard BitcoinAddress.isValid(address) else { return "" }
            return "bitcoin:\(address)\(c.cryptoAmount.isEmpty ? "" : "?amount=\(c.cryptoAmount)")"

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

    /// Deterministic UID for a calendar event: same event, same identifier on
    /// every render. Swift's `hashValue` is seeded per launch and cannot be
    /// used here — the encoded code must not change between two exports.
    private static func eventUID(_ e: EventFields) -> String {
        let stamp = e.start.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let slug = e.title.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24)
        return "\(stamp)-\(slug)@qr.code"
    }

    private static func utcStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}

/// Bitcoin address validation by checksum — enough to stop a mistyped address
/// from being printed on a poster and scanned by a stranger.
///
/// Two encodings carry an address: Base58Check (P2PKH `1…`, P2SH `3…`) and
/// bech32 / bech32m (segwit `bc1…`). Witness version 0 uses bech32, version 1
/// and above use bech32m — mixing the two is precisely the bug BIP350 fixed,
/// so the constant is chosen by version rather than assumed.
///
/// This proves the address is internally consistent. It cannot prove the
/// address exists on the chain or belongs to anyone — no offline check can.
enum BitcoinAddress {
    static func isValid(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        return isValidBase58Check(address) || isValidSegwit(address)
    }

    // MARK: - Base58Check

    private static let base58Alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    private static func isValidBase58Check(_ address: String) -> Bool {
        // Version 0x00 = P2PKH, 0x05 = P2SH: the mainnet prefixes we encode.
        guard let decoded = base58Decode(address), decoded.count == 25 else { return false }
        guard decoded[0] == 0x00 || decoded[0] == 0x05 else { return false }
        let payload = Data(decoded.prefix(21))
        let checksum = Array(decoded.suffix(4))
        let digest = SHA256.hash(data: Data(SHA256.hash(data: payload)))
        return Array(digest.prefix(4)) == checksum
    }

    /// Big-integer decode, least significant byte first, then reversed.
    private static func base58Decode(_ string: String) -> [UInt8]? {
        var littleEndian: [UInt8] = []
        for character in string {
            guard let digit = base58Alphabet.firstIndex(of: character) else { return nil }
            var carry = digit
            for i in littleEndian.indices {
                carry += 58 * Int(littleEndian[i])
                littleEndian[i] = UInt8(carry % 256)
                carry /= 256
            }
            while carry > 0 {
                littleEndian.append(UInt8(carry % 256))
                carry /= 256
            }
        }
        let leadingZeros = string.prefix { $0 == "1" }.count
        return [UInt8](repeating: 0, count: leadingZeros) + littleEndian.reversed()
    }

    // MARK: - Segwit (bech32 / bech32m)

    private static let bech32Alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let bech32Constant: UInt32 = 1
    private static let bech32mConstant: UInt32 = 0x2bc8_30a3

    private static func isValidSegwit(_ address: String) -> Bool {
        // Mixed case is invalid per BIP173; all-lower or all-upper is fine.
        guard !(address.contains(where: \.isUppercase) && address.contains(where: \.isLowercase)) else {
            return false
        }
        let lowered = address.lowercased()
        guard let separator = lowered.lastIndex(of: "1") else { return false }
        let hrp = String(lowered[lowered.startIndex..<separator])
        let dataPart = String(lowered[lowered.index(after: separator)...])
        guard hrp == "bc" || hrp == "tb" || hrp == "bcrt" else { return false }
        // Six checksum characters plus at least the witness version.
        guard dataPart.count >= 7, dataPart.count <= 90 else { return false }

        var values: [UInt8] = []
        for character in dataPart {
            guard let value = bech32Alphabet.firstIndex(of: character) else { return false }
            values.append(UInt8(value))
        }
        let version = values[0]
        guard version <= 16 else { return false }
        let checksum = Array(values.suffix(6))
        let data = Array(values.dropLast(6))
        let constant = version == 0 ? bech32Constant : bech32mConstant
        guard polymod(hrpExpand(hrp) + data + checksum) == constant else { return false }

        // Witness program: 2…40 bytes; 20 or 32 for v0, exactly 32 for v1+.
        guard let program = convertBits(Array(data.dropFirst()), from: 5, to: 8, pad: false),
              (2...40).contains(program.count) else { return false }
        if version == 0 {
            return program.count == 20 || program.count == 32
        }
        return program.count == 32
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        let generators: [UInt32] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3]
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ UInt32(value)
            for i in 0..<5 where (top >> UInt32(i)) & 1 == 1 {
                checksum ^= generators[i]
            }
        }
        return checksum
    }

    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var output: [UInt8] = []
        let maxValue = (1 << to) - 1
        for value in data {
            accumulator = (accumulator << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                output.append(UInt8((accumulator >> bits) & maxValue))
            }
        }
        if pad {
            if bits > 0 { output.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        } else if bits >= from || ((accumulator << (to - bits)) & maxValue) != 0 {
            return nil
        }
        return output
    }
}
