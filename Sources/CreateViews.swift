import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The studio screen, re-cut to Apple's own grammar: one inset-grouped list,
/// hero preview as the first cell, content form in native rows, export in
/// the toolbar. Nothing floats mid-scroll; the list IS the layout.
struct CreateView: View {
    @Bindable var model: AppModel
    @State private var preview: UIImage?
    @State private var exportDocument = QRDocument(data: Data())
    @State private var exportType: UTType = .png
    @State private var exporterPresented = false
    @State private var scoreSheetPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    previewCell
                }

                // The mode dial only makes sense for symbologies that can
                // carry structured payloads; linear codes hide it.
                if model.design.symbology.carriesRichPayload {
                    Section {
                        modeStrip
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Content") {
                    ContentForm(content: $model.content, symbology: model.design.symbology)
                }

                // A code with no content earns no score — showing "100
                // Excellent" for an empty symbol was exactly the kind of
                // dishonesty this report exists to prevent.
                if !model.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        scoreRow
                    }
                }
            }
            .listStyle(.insetGrouped)
            // No large title — the leading symbology pill names the canvas,
            // the bottom capsule names the verb. Redundant chrome.
            .toolbar {
                // Symbology is the canvas's identity — the leading system
                // pill slot, visible even mid-scroll.
                ToolbarItem(placement: .topBarLeading) {
                    symbologyMenu
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Progressive disclosure: history exists only once the
                    // first code has been shared or exported.
                    if !model.history.isEmpty {
                        Button {
                            Haptics.lightImpact()
                            model.historySheetPresented = true
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    exportMenu
                    settingsMenu
                }
            }
            .animation(.snappy(duration: 0.25), value: model.history.isEmpty)
            .sheet(isPresented: $model.designSheetPresented) {
                DesignSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $model.historySheetPresented) {
                HistoryView(model: model)
            }
            .sheet(isPresented: $scoreSheetPresented) {
                scoreSheet
            }
            // Regenerate the preview whenever inputs change. Rendering is
            // sub-millisecond on CoreImage; a tiny debounce still keeps
            // keystroke storms from re-rendering per character.
            .task(id: model.content) { await regenerate() }
            .task(id: model.design) { await regenerate() }
            .fileExporter(isPresented: $exporterPresented, document: exportDocument, contentType: exportType, defaultFilename: "qrcode-\(model.design.symbology.rawValue)") { result in
                switch result {
                case .success:
                    model.saveToHistory()
                    model.showToast("Saved — added to history")
                    Haptics.success()
                case .failure:
                    Haptics.error()
                }
            }
        }
    }

    // MARK: Toolbar items

    /// The symbology selector in the system slot: a leading toolbar pill,
    /// rendered by iOS 26 itself — always visible, even mid-scroll.
    private var symbologyMenu: some View {
        Menu {
            // A Picker inside the Menu rather than Buttons carrying an empty
            // systemImage: the empty image name logged a warning and misaligned
            // the menu, and this way the selection checkmark comes for free.
            Picker("Barcode type", selection: $model.design.symbology) {
                ForEach(Symbology.allCases) { sym in
                    Text(sym.title).tag(sym)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.design.symbology.title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Barcode type: \(model.design.symbology.title)")
        .accessibilityHint("Opens the symbology menu")
    }

    /// ONE export affordance, in the toolbar where Apple puts actions. The
    /// system share sheet covers Photos/Files/AirDrop; Files export adds
    /// PNG and print-grade PDF without a second button on screen.
    private var exportMenu: some View {
        Menu {
            if let preview {
                ShareLink(item: Image(uiImage: preview),
                          preview: SharePreview(model.summary, image: Image(uiImage: preview))) {
                    Label("Share Image…", systemImage: "square.and.arrow.up")
                }
                .simultaneousGesture(TapGesture().onEnded { model.saveToHistory() })
                Button { export(.png) } label: {
                    Label("Save PNG to Files", systemImage: "folder")
                }
                Button { export(.pdf) } label: {
                    Label("Save PDF for Print", systemImage: "printer")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(preview == nil)
        .accessibilityLabel("Export QR code")
    }

    /// Settings affordance next to export — secondary actions that aren't
    /// part of the create loop: another path into Design, and a way back
    /// to defaults after experimentation.
    private var settingsMenu: some View {
        Menu {
            Button {
                model.designSheetPresented = true
            } label: {
                Label("Design…", systemImage: "paintpalette")
            }
            Button {
                let symbology = model.design.symbology
                model.design = DesignOptions()
                model.design.symbology = symbology
                model.showToast("Design reset to defaults")
                Haptics.lightImpact()
            } label: {
                Label("Reset Design", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Settings")
    }

    // MARK: Cells

    /// The hero: the code itself, on a plain list cell. No buttons, no
    /// frame-within-a-frame — the quiet zone is the margin.
    private var previewCell: some View {
        VStack(spacing: 10) {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    // Rendered at 1024px and shown at ~840px on a 3× screen:
                    // nearest-neighbour at a non-integer ratio drops and
                    // duplicates whole module rows, so modules look unevenly
                    // sized on screen while the exported file stays perfect.
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .padding(.vertical, 6)
                    .accessibilityLabel("QR code preview for \(model.summary)")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 44))
                        .foregroundStyle(.quaternary)
                    Text("Enter content to activate this code")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 48)
            }
            if !model.payload.isEmpty {
                Text(model.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Camera-style mode dial: eleven modes scroll horizontally in unfilled
    /// capsules; the selected one takes a soft accent tint — the App Store
    /// filter idiom, not a solid marketing pill.
    private var modeStrip: some View {
        // ScrollViewReader keeps the selected capsule visible — the Camera-
        // app rule applies to scrolling too: the current mode is never
        // hidden, even when the change came from a history restore.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ContentType.allCases) { type in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy(duration: 0.2)) { model.content.type = type }
                        } label: {
                            Label(type.title, systemImage: type.systemImage)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    model.content.type == type
                                        ? Color.accentColor.opacity(0.14)
                                        : Color(.secondarySystemGroupedBackground),
                                    in: Capsule()
                                )
                                .foregroundStyle(model.content.type == type ? Color.accentColor : .primary)
                        }
                        .id(type.id)
                        .accessibilityAddTraits(model.content.type == type ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(model.content.type.id, anchor: .center) }
            .onChange(of: model.content.type) { _, new in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(new.id, anchor: .center) }
            }
        }
    }

    /// Scanability as ONE quiet row — grade plus a mini ring. The full
    /// checklist is disclosed on demand, never waved at the user mid-flow.
    private var scoreRow: some View {
        // A Button rather than a tap gesture with an .isButton trait. The trait
        // made VoiceOver announce it correctly, but Switch Control and Full
        // Keyboard Access could not activate it.
        Button {
            scoreSheetPresented = true
        } label: {
            HStack(spacing: 12) {
                MiniScoreRing(score: model.report.score)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.report.grade)
                        .font(.subheadline.weight(.medium))
                    Text("Scanability report")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanability \(model.report.score) of 100, \(model.report.grade). Opens the full report.")
    }

    private var scoreSheet: some View {
        NavigationStack {
            List {
                Section {
                    ScoreRing(score: model.report.score, grade: model.report.grade)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                Section("Checks") {
                    ForEach(model.report.checks) { check in
                        CheckRow(check: check)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Scanability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { scoreSheetPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Actions

    private func regenerate() async {
        // Debounce only once a preview exists — the first render should be
        // instant (no placeholder flash on launch), later edits coalesce.
        if preview != nil {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
        }
        let payload = model.payload
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { preview = nil }
            return
        }
        let design = model.design
        let img = await Task.detached(priority: .userInitiated) {
            QRRenderer.image(payload: payload, design: design)
        }.value
        await MainActor.run { preview = img }
    }

    private func export(_ type: UTType) {
        let payload = model.payload
        let design = model.design
        // Off the main thread. A dense styled code is ~31,000 vector subpaths
        // and the PDF path also rasterises at 2048px; done synchronously this
        // was a visible hang, and a watchdog kill on older hardware. The
        // preview path already detached — this is the same discipline, with
        // only Sendable values crossing into the detached task.
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) {
                type == .pdf
                    ? QRRenderer.pdfData(payload: payload, design: design)
                    : QRRenderer.pngData(payload: payload, design: design)
            }.value
            guard let data else {
                Haptics.error()
                model.showToast("Export failed")
                return
            }
            exportType = type
            exportDocument = QRDocument(data: data)
            exporterPresented = true
        }
    }
}

/// File-export wrapper for the system document picker.
struct QRDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .pdf] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}
