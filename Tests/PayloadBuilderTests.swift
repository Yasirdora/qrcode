import XCTest
@testable import QRFlow

/// Pinned by the same runtime assertions that shipped green in the
/// command-line harness (15/15) before this file existed.
final class PayloadBuilderTests: XCTestCase {

    func testWiFiEscapesReservedCharacters() {
        var c = ContentState()
        c.type = .wifi
        c.wifi.ssid = "My;Home"
        c.wifi.password = #"p:a\ss"#
        XCTAssertEqual(PayloadBuilder.payload(for: c), #"WIFI:T:WPA;S:My\;Home;P:p\:a\\ss;;"#)
    }

    func testURLPassesExistingSchemesThrough() {
        var c = ContentState()
        c.url = "mailto:a@b.com"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "mailto:a@b.com")
        c.url = "yourapp://deep/link"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "yourapp://deep/link")
    }

    func testURLPrependsHTTPSForBareDomains() {
        var c = ContentState()
        c.url = "example.com"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "https://example.com")
    }

    func testWhatsAppStripsFormattingAndEncodesMessage() {
        var c = ContentState()
        c.type = .whatsapp
        c.whatsappNumber = "+1 (555) 123-4567"
        c.whatsappMessage = "Hi there"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "https://wa.me/15551234567?text=Hi%20there")
    }

    func testVCardStructure() {
        var c = ContentState()
        c.type = .vcard
        c.vcard.firstName = "Ada"
        c.vcard.lastName = "Lovelace"
        c.vcard.phone = "+49123"
        let payload = PayloadBuilder.payload(for: c)
        XCTAssertTrue(payload.contains("BEGIN:VCARD"))
        XCTAssertTrue(payload.contains("N:Lovelace;Ada;;;"))
        XCTAssertTrue(payload.contains("TEL;TYPE=CELL:+49123"))
        XCTAssertTrue(payload.hasSuffix("END:VCARD"))
    }

    func testEventRequiresTitleAndStart() {
        var c = ContentState()
        c.type = .event
        XCTAssertEqual(PayloadBuilder.payload(for: c), "")
        c.event.title = "Launch"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "")
        c.event.start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(PayloadBuilder.payload(for: c).contains("SUMMARY:Launch"))
    }

    func testEmptyInputsProduceEmptyPayloads() {
        for type in ContentType.allCases {
            var c = ContentState()
            c.type = type
            c.url = ""
            // phone/geo/whatsapp/custom stay empty; url cleared above
            if type == .url || type == .phone || type == .geo || type == .whatsapp || type == .custom {
                XCTAssertEqual(PayloadBuilder.payload(for: c), "", "\(type) should be empty")
            }
        }
    }

    func testEstimateVersionBounds() {
        XCTAssertEqual(PayloadBuilder.estimateVersion(bytes: 0, ec: .h), 1)
        XCTAssertEqual(PayloadBuilder.estimateVersion(bytes: 10, ec: .h), 2)
        XCTAssertEqual(PayloadBuilder.estimateVersion(bytes: 5000, ec: .l), 41)
    }

    func testSummariesNeverExposeRawPayloads() {
        var c = ContentState()
        c.type = .wifi
        c.wifi.ssid = "CafeNet"
        XCTAssertEqual(PayloadBuilder.summarize(c), "Wi-Fi · CafeNet")

        var v = ContentState()
        v.type = .vcard
        v.vcard.firstName = "Ada"
        v.vcard.lastName = "Lovelace"
        XCTAssertEqual(PayloadBuilder.summarize(v), "Contact · Ada Lovelace")
    }

    // MARK: - Context band destination labels

    func testDestinationLabelNeverLeaksWiFiPassword() {
        let label = QRRenderer.destinationLabel(payload: "WIFI:T:WPA;S:CafeGuest;P:hunter2;;")
        XCTAssertEqual(label, "Wi-Fi: CafeGuest")
        XCTAssertFalse(label.contains("hunter2"), "the band prints under the code on posters")
    }

    func testDestinationLabelEscapesSSIDCorrectly() {
        // Backslash-escaped separators in the SSID must not split the field.
        let label = QRRenderer.destinationLabel(payload: #"WIFI:T:WPA;S:Cafe\;5;P:secret;;"#)
        XCTAssertEqual(label, "Wi-Fi: Cafe;5")
    }

    func testDestinationLabelUsesVCardName() {
        let label = QRRenderer.destinationLabel(payload: "BEGIN:VCARD\nVERSION:3.0\nFN:Ada Lovelace\nTEL:+49123\nEND:VCARD")
        XCTAssertEqual(label, "Ada Lovelace")
    }

    func testDestinationLabelTruncatesCryptoAddress() {
        let label = QRRenderer.destinationLabel(payload: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")
        XCTAssertTrue(label.hasPrefix("Bitcoin: bc1qxy2kgd"))
        XCTAssertTrue(label.contains("…"), "full address would clutter the band")
    }

    func testDestinationLabelKeepsURLHost() {
        XCTAssertEqual(QRRenderer.destinationLabel(payload: "https://www.github.com/user/repo"), "github.com")
    }

    // MARK: - Encoded-record correctness

    func testCryptoRefusesAnAddressThatFailsItsChecksum() {
        var c = ContentState()
        c.type = .crypto
        c.cryptoAddress = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" // genesis block
        XCTAssertEqual(PayloadBuilder.payload(for: c), "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa")

        // One character changed: the checksum no longer verifies, and the code
        // must not be offered at all.
        c.cryptoAddress = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb"
        XCTAssertEqual(PayloadBuilder.payload(for: c), "")
    }

    func testBitcoinAddressAcceptsKnownVectors() {
        // Base58Check P2PKH, Base58Check P2SH, and the BIP173 bech32 vector.
        for address in ["1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                        "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2",
                        "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",
                        "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"] {
            XCTAssertTrue(BitcoinAddress.isValid(address), "\(address) should validate")
        }
        for address in ["", "1", "0OIl",
                        "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb",           // bad checksum
                        "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5",   // bad checksum
                        "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"] { // scheme included
            XCTAssertFalse(BitcoinAddress.isValid(address), "\(address) should be rejected")
        }
    }

    func testVCardJoinsWithCRLFAndEscapesEveryValue() {
        var c = ContentState()
        c.type = .vcard
        c.vcard.firstName = "Ada"
        c.vcard.lastName = "Lovelace"
        c.vcard.phone = "+49;123"
        let payload = PayloadBuilder.payload(for: c)
        XCTAssertTrue(payload.contains(#"TEL;TYPE=CELL:+49\;123"#),
                      "a semicolon in a phone number must not start a new field")
        XCTAssertTrue(payload.contains("\r\n"), "vCard 3.0 requires CRLF")
        XCTAssertFalse(payload.replacingOccurrences(of: "\r\n", with: "").contains("\n"),
                       "no bare LF may remain")
    }

    func testEventPayloadIsAWrappedICalendarRecordAndIsStable() {
        var c = ContentState()
        c.type = .event
        c.event.title = "Launch party"
        c.event.start = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = PayloadBuilder.payload(for: c)
        for expected in ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:",
                         "DTSTAMP:", "SUMMARY:Launch party", "DTSTART:",
                         "END:VEVENT", "END:VCALENDAR"] {
            XCTAssertTrue(payload.contains(expected), "missing \(expected)")
        }
        XCTAssertTrue(payload.contains("\r\n"), "iCalendar requires CRLF")
        // Deterministic: the payload is recomputed on every render, so a
        // randomly generated UID would change the printed code between two
        // exports of the same design.
        XCTAssertEqual(payload, PayloadBuilder.payload(for: c))
    }
}
