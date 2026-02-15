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
}
