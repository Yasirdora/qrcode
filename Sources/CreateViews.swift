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
    @State private var batchPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.gutter) {
                    heroCard
                    // The actions only exist once there is something to act on;
                    // the empty state above says what to do instead of offering
                    // buttons that cannot work.
                    if preview != nil {
                        actionBar
                    }
                    if model.design.symbology.carriesRichPayload {
                        modeStrip
                    }
                    contentCard
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, Theme.tight)
            }
            .background(Theme.page)
            // No large title: the leading pill names the symbology, the bar names
            // the destinations. A third title would be chrome.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    symbologyMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
                }
            }
            // The scanability report stays a sheet: it is a detail you consult
            // and dismiss, not a place.
            .sheet(isPresented: $scoreSheetPresented) {
                scoreSheet
            }
            .sheet(isPresented: $batchPresented) {
                BatchSheet(model: model)
            }
            // Regenerate whenever inputs change. Rendering is sub-millisecond on
            // CoreImage; the small debounce only keeps keystroke storms from
            // re-rendering per character.
            .task(id: model.content) { await regenerate() }
            .task(id: model.design) { await regenerate() }
            .fileExporter(isPresented: $exporterPresented, document: exportDocument, contentType: exportType, defaultFilename: "qrcode-\(model.design.symbology.rawValue)") { result in
                switch result {
                case .success:
                    model.saveToHistory()
                    model.showToast("Saved to your library")
                    Haptics.success()
                case .failure:
                    Haptics.error()
                }
            }
        }
    }

    // MARK: Hero and actions

    /// The code is the point of the screen, so it gets the one surface that is
    /// not chrome: paper. The score is attached to it rather than sitting in a
    /// row of its own, because the score is a property of this code.
    private var heroCard: some View {
        VStack(spacing: 0) {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        // Rendered at 1024px and shown at ~840px on a 3× screen:
                        // nearest-neighbour at a non-integer ratio drops and
                        // duplicates whole module rows.
                        .interpolation(.high)
                        .scaledToFit()
                        .accessibilityLabel("QR code for \(model.summary)")
                } else {
                    VStack(spacing: Theme.tight) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.ink.opacity(0.18))
                        Text("Enter content to activate this code")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.55))
                    }
                    .padding(.vertical, 56)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.cardPadding)
            .padding(.bottom, Theme.tight)

            if preview != nil, !model.payload.isEmpty {
                Text(model.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.bottom, Theme.cardPadding)

                Divider()
                    .overlay(Theme.ink.opacity(0.12))

                scoreLine
            } else {
                EmptyView()
            }
        }
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.card, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 0.5)
        )
    }

    /// The score, on the code's own card, opening the full report when tapped.
    private var scoreLine: some View {
        Button {
            scoreSheetPresented = true
        } label: {
            HStack(alignment: .center, spacing: Theme.cardPadding) {
                Text("\(model.report.score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(model.report.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.report.grade)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Scanability")
                        .font(.caption)
                        .foregroundStyle(Theme.ink.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink.opacity(0.3))
            }
            .padding(Theme.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scanability \(model.report.score) of 100, \(model.report.grade). Opens the full report.")
    }

    /// The three things a person does with a finished code, as pills rather than
    /// toolbar glyphs: share it, save a raster, save a vector. Print-grade PDF,
    /// batching and reset live behind the overflow.
    private var actionBar: some View {
        HStack(spacing: Theme.tight) {
            if let preview {
                ShareLink(item: Image(uiImage: preview),
                          preview: SharePreview(model.summary, image: Image(uiImage: preview))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .simultaneousGesture(TapGesture().onEnded { model.saveToHistory() })
            }
            Button {
                export(.png)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            // Vector output is QR-only: the other symbologies are CoreImage
            // bitmaps with no module geometry to serialise, so the pill appears
            // only where it can be honoured.
            if model.design.symbology == .qr {
                Button {
                    export(.svg)
                } label: {
                    Text("SVG").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Save as SVG")
            }
        }
    }

    /// The fields, in a card rather than a grouped list: a list made this read
    /// like Settings, and these are steps on the way to a code.
    private var contentCard: some View {
        ContentForm(content: $model.content, symbology: model.design.symbology)
            .padding(Theme.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.card, style: .continuous))
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

    /// Everything that is not part of the create loop.
    private var overflowMenu: some View {
        Menu {
            Button {
                export(.pdf)
            } label: {
                Label("Save PDF for Print", systemImage: "printer")
            }
            .disabled(preview == nil)
            Button {
                batchPresented = true
            } label: {
                Label("Generate from a List…", systemImage: "list.bullet.rectangle")
            }
            Divider()
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
        .accessibilityLabel("More actions")
    }

    // MARK: Mode strip

    /// The content types as a scrolling row of capsules. The selection takes a
    /// soft accent tint — the filter idiom, not a solid marketing pill.
    private var modeStrip: some View {
        // ScrollViewReader keeps the selected capsule visible: the current mode
        // is never hidden, even when a restore is what changed it.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.tight) {
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
                                        ? Theme.accent.opacity(0.14)
                                        : Theme.surface,
                                    in: Capsule()
                                )
                                .foregroundStyle(model.content.type == type ? Theme.accent : .primary)
                        }
                        .id(type.id)
                        .accessibilityAddTraits(model.content.type == type ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(model.content.type.id, anchor: .center) }
            .onChange(of: model.content.type) { _, new in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(new.id, anchor: .center) }
            }
        }
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
                switch type {
                case .pdf: QRRenderer.pdfData(payload: payload, design: design)
                case .svg: QRRenderer.svg(payload: payload, design: design)?.data(using: .utf8)
                default: QRRenderer.pngData(payload: payload, design: design)
                }
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
    static var readableContentTypes: [UTType] { [.png, .pdf, .svg] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}

/// Paste one payload per line; get one print-ready page per code — the code
/// itself, and the text it encodes so the pages stay identifiable.
private struct BatchSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var document = QRDocument(data: Data())
    @State private var exporting = false
    @State private var busy = false
    @State private var count = 0

    private var payloads: [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("One payload per line — URLs, Wi-Fi strings, or anything the selected symbology can carry. Each becomes a page of one PDF: the code, and the text it encodes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.footnote.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 220)
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(count == 1 ? "1 payload" : "\(count) payloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .navigationTitle("Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Export PDF") { generate() }
                            .disabled(payloads.isEmpty)
                    }
                }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .pdf,
                          defaultFilename: "qrcode-batch-\(count)") { result in
                switch result {
                case .success:
                    Haptics.success()
                    model.showToast("Saved \(count) codes")
                case .failure:
                    Haptics.error()
                }
                dismiss()
            }
            .task(id: text) {
                // Counting is cheap; rendering is not, so the count is live and
                // the work happens on demand.
                let lines = payloads.count
                guard lines != count else { return }
                count = lines
            }
        }
    }

    private func generate() {
        let list = payloads
        let design = model.design
        busy = true
        Task { @MainActor in
            let data = await Task.detached(priority: .userInitiated) {
                QRRenderer.batchPDF(payloads: list, design: design)
            }.value
            busy = false
            guard let data else {
                Haptics.error()
                model.showToast("Nothing to generate")
                return
            }
            document = QRDocument(data: data)
            exporting = true
        }
    }
}
