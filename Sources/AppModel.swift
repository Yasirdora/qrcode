import SwiftUI

/// Single source of truth — the handoff's one-`@Observable`-model pattern.
/// All state, navigation and persistence live here; views stay dumb.
/// @MainActor because every mutation originates from UI events.
@MainActor
@Observable
final class AppModel {
    /// Three destinations on one side of the bar. The scanner is an action, not
    /// a place: it lives on the other side and opens over everything, the way a
    /// camera should.
    enum Tab: Hashable, CaseIterable {
        case create, design, library

        var title: String {
            switch self {
            case .create: "Create"
            case .design: "Design"
            case .library: "Library"
            }
        }

        var image: String {
            switch self {
            case .create: "qrcode"
            case .design: "paintpalette"
            case .library: "square.grid.2x2"
            }
        }
    }

    var tab: Tab = .create
    var scanPresented = false
    var content = ContentState()
    var design = DesignOptions()
    private(set) var history: [HistoryEntry] = []

    var toast: String?
    private var toastTask: Task<Void, Never>?

    var onboardingComplete: Bool {
        didSet { defaults.set(onboardingComplete, forKey: Key.onboarding) }
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let onboarding = "qrflow.onboardingComplete"
        static let history = "qrflow.history"
    }

    init() {
        onboardingComplete = defaults.bool(forKey: Key.onboarding)
        if let data = defaults.data(forKey: Key.history),
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            history = entries
        }
        #if DEBUG
        // UI-verification hooks, same philosophy as the handoff's
        // -ui-testing args: -ui-type=wifi forces a mode, -ui-seed-history
        // injects one sample entry (in memory only) so the gated history
        // button can be verified without a real export.
        let args = ProcessInfo.processInfo.arguments
        // -ui-onboarded skips onboarding so the studio surfaces can be
        // captured headlessly.
        if args.contains("-ui-onboarded") {
            onboardingComplete = true
        }
        if let i = args.firstIndex(of: "-ui-type"), i + 1 < args.count,
           let forced = ContentType(rawValue: args[i + 1]) {
            content.type = forced
        }
        if let i = args.firstIndex(of: "-ui-sym"), i + 1 < args.count,
           let forced = Symbology(rawValue: args[i + 1]) {
            design.symbology = forced
            if !forced.carriesRichPayload, content.barcodeValue.isEmpty {
                // A valid sample so screenshots show a rendered symbol.
                content.barcodeValue = forced == .code128 ? "QRFLOW-2026"
                    : forced == .ean8 ? "96385074" : "4006381333931"
            }
        }
        // -ui-tab=<create|design|library|scan> opens a destination for headless
        // screenshot verification. "scan" opens the camera cover, because the
        // scanner is no longer a tab.
        if let i = args.firstIndex(of: "-ui-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "design": tab = .design
            case "library": tab = .library
            case "scan": scanPresented = true
            default: tab = .create
            }
        }
        if args.contains("-ui-design") {
            tab = .design
        }
        if args.contains("-ui-seed-history"), history.isEmpty {
            history = [HistoryEntry(id: UUID(), createdAt: Date(),
                                    content: ContentState(), design: DesignOptions())]
        }
        // -ui-style=<preset> forces a module-styling preset so the styled
        // renderer can be screenshot-verified without driving the UI.
        if let i = args.firstIndex(of: "-ui-style"), i + 1 < args.count {
            switch args[i + 1] {
            case "dots":
                design.dotType = .dots
                design.cornerSquareType = .dot
                design.cornerDotType = .dot
            case "fluid":
                design.dotType = .fluid
                design.cornerSquareType = .extraRounded
                design.cornerDotType = .dot
            case "gradient":
                design.dotType = .rounded
                design.gradientEnabled = true
            case "transparent":
                design.transparentBg = true
            case "full":
                design.dotType = .rounded
                design.cornerSquareType = .extraRounded
                design.cornerDotType = .dot
                design.gradientEnabled = true
            default: break
            }
        }
        #endif
    }

    // MARK: Derived

    var payload: String { PayloadBuilder.payload(for: content, symbology: design.symbology) }
    var summary: String {
        design.symbology.carriesRichPayload
            ? PayloadBuilder.summarize(content)
            : content.barcodeValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var report: Scanability.Report { Scanability.score(payload: payload, design: design) }

    // MARK: History

    func saveToHistory() {
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Dedupe on the design itself. Comparing against a freshly generated
        // UUID could never match, so saving the same code twice piled up two
        // identical entries.
        history.removeAll { $0.content == content && $0.design == design }
        history.insert(HistoryEntry(id: UUID(), createdAt: Date(), content: content, design: design), at: 0)
        if history.count > 30 { history = Array(history.prefix(30)) }
        persistHistory()
    }

    func deleteHistory(_ id: UUID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    func restore(_ entry: HistoryEntry) {
        content = entry.content
        design = entry.design
        tab = .create
        showToast("Design restored — keep editing")
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toastTask?.cancel()
        // Announced from here, not from the view: the toast view is transient
        // and may be reused for a repeated message, which would swallow an
        // appear-time announcement. This is the single choke point.
        AccessibilityNotification.Announcement(message).post()
        withAnimation(.smooth(duration: 0.3)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.3)) { self.toast = nil }
        }
    }
}
