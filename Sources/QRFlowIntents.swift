import AppIntents
import UniformTypeIdentifiers
import UIKit

/// Siri/Shortcuts integration — the #1 gap in the QR-app market: every
/// competitor stops at "open app, paste, export". QRFlow codes are one
/// voice command or one Shortcuts automation away, rendered by the same
/// pixel-quantized engine as the app itself.
///
/// Pure model reuse: intents build a ContentState/DesignOptions and call
/// the exact same PayloadBuilder/QRRenderer pipeline the UI uses, so a
/// Siri-made code is indistinguishable from a hand-crafted one.

enum QRFlowIntentError: Error, LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: "The content could not be encoded as a QR code."
        }
    }
}

/// Renders a code for the intent pipeline. Intents always produce QR
/// symbols (the only symbology that carries arbitrary payloads), at print-
/// friendly 1024px with the ISO quiet zone, plain square style for maximum
/// scannability.
private func renderIntentPNG(payload: String) throws -> Data {
    var design = DesignOptions()
    design.exportSize = 1024
    guard let image = QRRenderer.image(payload: payload, design: design),
          let png = image.pngData() else {
        throw QRFlowIntentError.renderFailed
    }
    return png
}

// MARK: - Make QR Code

struct MakeQRCodeIntent: AppIntent {
    static var title: LocalizedStringResource { "Make QR Code" }
    static var description: IntentDescription {
        IntentDescription("Creates a QR code image from any text or link — ready to share or save.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Content",
               description: "The link or text the QR code should open.",
               inputOptions: String.IntentInputOptions(capitalizationType: .none))
    var content: String

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QRFlowIntentError.renderFailed }
        let png = try renderIntentPNG(payload: trimmed)
        return .result(value: IntentFile(data: png, filename: "qr-code.png", type: .png))
    }
}

// MARK: - Make Wi-Fi QR Code

struct MakeWiFiQRIntent: AppIntent {
    static var title: LocalizedStringResource { "Make Wi-Fi QR Code" }
    static var description: IntentDescription {
        IntentDescription("Creates a QR code that joins guests to a Wi-Fi network when scanned.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Network name (SSID)")
    var ssid: String

    @Parameter(title: "Password", inputOptions: String.IntentInputOptions(capitalizationType: .none))
    var password: String

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard !ssid.isEmpty else { throw QRFlowIntentError.renderFailed }
        var content = ContentState()
        content.type = .wifi
        content.wifi = WiFiFields(ssid: ssid, password: password, encryption: "WPA", hidden: false)
        let payload = PayloadBuilder.payload(for: content, symbology: .qr)
        let png = try renderIntentPNG(payload: payload)
        return .result(value: IntentFile(data: png, filename: "wifi-qr.png", type: .png))
    }
}

// MARK: - Siri phrases

struct QRFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MakeQRCodeIntent(),
            phrases: [
                "Make a QR code with \(.applicationName)",
                "Make a QR code in \(.applicationName)",
            ],
            shortTitle: "Make QR Code",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: MakeWiFiQRIntent(),
            phrases: [
                "Share my Wi-Fi with \(.applicationName)",
                "Make a Wi-Fi QR code with \(.applicationName)",
            ],
            shortTitle: "Wi-Fi QR Code",
            systemImageName: "wifi"
        )
    }
}
