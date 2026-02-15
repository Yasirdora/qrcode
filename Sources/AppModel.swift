import SwiftUI

/// Single source of truth — the handoff's one-`@Observable`-model pattern.
/// All state, navigation and persistence live here; views stay dumb.
/// @MainActor because every mutation originates from UI events.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case create, scan
    }

    var tab: Tab = .create
    var content = ContentState()
    var design = DesignOptions()
    var designSheetPresented = false
    var historySheetPresented = false
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
        // -ui-tab=scan opens the Scan surface; -ui-design presents the
        // design sheet — both for headless screenshot verification.
        if let i = args.firstIndex(of: "-ui-tab"), i + 1 < args.count, args[i + 1] == "scan" {
            tab = .scan
        }
        if args.contains("-ui-design") {
            designSheetPresented = true
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
        let entry = HistoryEntry(id: UUID(), createdAt: Date(), content: content, design: design)
        history.removeAll { $0.id == entry.id }
        history.insert(entry, at: 0)
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
        withAnimation(.smooth(duration: 0.3)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.3)) { self.toast = nil }
        }
    }
}
