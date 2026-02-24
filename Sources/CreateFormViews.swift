import SwiftUI
import PhotosUI
import ContactsUI

/// Per-type input forms. Field order matches the web studio so the two apps
/// feel like one product.
struct ContentForm: View {
    @Binding var content: ContentState
    var symbology: Symbology = .qr
    @State private var contactPickerPresented = false
    /// The Wi-Fi password field is masked by default; this drives its reveal.
    @State private var wifiPasswordVisible = false

    var body: some View {
        if !symbology.carriesRichPayload {
            // Linear codes carry one raw value — the mode strip and its
            // structured fields are irrelevant for these symbologies.
            LabeledField("\(symbology.title) value") {
                TextField(symbology.valueHint, text: $content.barcodeValue)
                    .keyboardType(symbology == .code128 ? .asciiCapable : .numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } else {
            richPayloadForm
        }
    }

    @ViewBuilder
    private var richPayloadForm: some View {
        switch content.type {
        case .url:
            LabeledField("Destination URL") {
                TextField("https://your-site.com", text: $content.url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .text:
            LabeledField("Plain text") {
                TextField("Serial numbers, coupons, notes…", text: $content.text, axis: .vertical)
                    .lineLimit(3...6)
            }
        case .wifi:
            LabeledField("Network name (SSID)") { TextField("MyHomeWifi", text: $content.wifi.ssid) }
            // Masked by default: the Wi-Fi password is the one secret this app
            // handles, and a plain field exposes it to shoulder-surfing,
            // screenshots and screen recording.
            LabeledField("Password") {
                HStack(spacing: 8) {
                    Group {
                        if wifiPasswordVisible {
                            TextField("Password", text: $content.wifi.password)
                        } else {
                            SecureField("Password", text: $content.wifi.password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button {
                        wifiPasswordVisible.toggle()
                    } label: {
                        Image(systemName: wifiPasswordVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(wifiPasswordVisible ? "Hide password" : "Show password")
                }
            }
            Picker("Security", selection: $content.wifi.encryption) {
                Text("WPA/WPA2/WPA3").tag("WPA")
                Text("WEP").tag("WEP")
                Text("Open").tag("nopass")
            }
            Toggle("Hidden network", isOn: $content.wifi.hidden)
        case .vcard:
            // Nobody should retype a contact that already exists on the
            // phone. The picker runs out of process — it needs no Contacts
            // permission and the app only receives the card the user picks.
            Button {
                contactPickerPresented = true
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .sheet(isPresented: $contactPickerPresented) {
                ContactPicker { contact in
                    content.vcard.firstName = contact.givenName
                    content.vcard.lastName = contact.familyName
                    content.vcard.org = contact.organizationName
                    content.vcard.title = contact.jobTitle
                    content.vcard.phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                    content.vcard.email = contact.emailAddresses.first.map { $0.value as String } ?? ""
                    content.vcard.url = contact.urlAddresses.first.map { $0.value as String } ?? ""
                }
            }
            LabeledField("First name") { TextField("Ada", text: $content.vcard.firstName) }
            LabeledField("Last name") { TextField("Lovelace", text: $content.vcard.lastName) }
            LabeledField("Phone") { TextField("+49 …", text: $content.vcard.phone).keyboardType(.phonePad) }
            LabeledField("Email") { TextField("ada@example.com", text: $content.vcard.email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }
            LabeledField("Company") { TextField("Company", text: $content.vcard.org) }
            LabeledField("Job title") { TextField("Title", text: $content.vcard.title) }
            LabeledField("Website") { TextField("https://…", text: $content.vcard.url).keyboardType(.URL).textInputAutocapitalization(.never) }
        case .email:
            LabeledField("To") {
                TextField("ada@example.com", text: $content.emailTo)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledField("Subject") { TextField("Subject", text: $content.emailSubject) }
            LabeledField("Message") {
                TextField("Body", text: $content.emailBody, axis: .vertical)
                    .lineLimit(3...6)
            }
        case .sms:
            LabeledField("Phone number") { TextField("+1 555 123 4567", text: $content.smsNumber).keyboardType(.phonePad) }
            LabeledField("Message") { TextField("Pre-filled message", text: $content.smsMessage, axis: .vertical).lineLimit(2...4) }
        case .phone:
            LabeledField("Phone number") { TextField("+1 555 123 4567", text: $content.phoneNumber).keyboardType(.phonePad) }
        case .geo:
            LabeledField("Latitude") { TextField("37.7749", text: $content.geoLat).keyboardType(.numbersAndPunctuation) }
            LabeledField("Longitude") { TextField("-122.4194", text: $content.geoLng).keyboardType(.numbersAndPunctuation) }
        case .event:
            LabeledField("Event title") { TextField("Launch party", text: $content.event.title) }
            // The pickers WRITE their value on first appearance. The old
            // binding only substituted `.now` on read, so a filled-in title
            // plus an untouched date left `start` nil and the payload empty —
            // the screen showed a date the encoder never saw.
            DatePicker("Starts", selection: Binding($content.event.start, replacingNilWith: .now), displayedComponents: [.date, .hourAndMinute])
                .onAppear { if $content.event.start.wrappedValue == nil { $content.event.start.wrappedValue = .now } }
            DatePicker("Ends", selection: Binding($content.event.end, replacingNilWith: .now.addingTimeInterval(3600)), displayedComponents: [.date, .hourAndMinute])
                .onAppear { if $content.event.end.wrappedValue == nil { $content.event.end.wrappedValue = .now.addingTimeInterval(3600) } }
            LabeledField("Location") { TextField("Location", text: $content.event.location) }
        case .crypto:
            LabeledField("Bitcoin address") { TextField("bc1q…", text: $content.cryptoAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
            // Inline validation: the encoder refuses an address that fails its
            // checksum, and without this the refusal would look like a bug.
            if !content.cryptoAddress.isEmpty, !BitcoinAddress.isValid(content.cryptoAddress) {
                Label("This address is not valid: its checksum does not match.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledField("Amount (BTC, optional)") { TextField("0.001", text: $content.cryptoAmount).keyboardType(.decimalPad) }
        case .whatsapp:
            LabeledField("Phone number (with country code)") { TextField("+1 555 123 4567", text: $content.whatsappNumber).keyboardType(.phonePad) }
            LabeledField("Pre-filled message (optional)") { TextField("Hi! I scanned your code…", text: $content.whatsappMessage, axis: .vertical).lineLimit(2...4) }
        case .custom:
            LabeledField("Raw payload — encoded byte for byte") {
                TextField("BCD\n002\n1\nSCT …", text: $content.customText, axis: .vertical)
                    .font(.footnote.monospaced())
                    .lineLimit(4...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Text("Power-user mode: SEPA/EPC bank transfers, app deep links, proprietary schemes — if a scanner understands it, you can encode it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        // Native list-row grammar: a small caption over a bare field, like
        // Contacts editing — no boxes inside boxes.
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content
        }
    }
}

extension Binding {
    /// Wraps an optional binding, substituting a default when nil.
    init(_ source: Binding<Value?>, replacingNilWith defaultValue: @autoclosure @escaping @Sendable () -> Value) where Value: Equatable & Sendable {
        self.init(
            get: { source.wrappedValue ?? defaultValue() },
            set: { source.wrappedValue = $0 }
        )
    }
}

/// Design settings — a sheet, not a step (the same UX ruling as the web app).
struct DesignSheet: View {
    @Bindable var model: AppModel
    @State private var logoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                // Live preview inside the sheet: design decisions should
                // never be blind — the sheet updates the code as you tap.
                // The container is always white: a QR needs a clean stage,
                // not the grouped-form grey.
                Section {
                    DesignPreviewCell(model: model)
                        .listRowBackground(Color.white)
                }

                // Curated looks — one tap applies a whole coherent design,
                // then every control below still allows fine-tuning.
                if model.design.symbology == .qr {
                    Section("Themes") {
                        ThemeGallery(model: model)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Colors") {
                    ColorPicker("Module color", selection: hexBinding(\.fgHex), supportsOpacity: false)
                    ColorPicker("Background", selection: hexBinding(\.bgHex), supportsOpacity: false)
                }

                // Module styling is the web studio's signature vocabulary —
                // QR only; other symbologies render through CoreImage/EAN
                // paths that carry no shape options. Shapes are picked
                // visually: you choose what you SEE, not a word in a menu.
                if model.design.symbology == .qr {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dot shape").font(.subheadline)
                            ShapeGallery(items: DotType.allCases,
                                         selected: model.design.dotType,
                                         title: { $0.title },
                                         glyph: { dotGlyph(for: $0) }) { model.design.dotType = $0 }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Eye frame").font(.subheadline)
                            ShapeGallery(items: CornerSquareType.allCases,
                                         selected: model.design.cornerSquareType,
                                         title: { $0.title },
                                         glyph: { eyeFrameGlyph(for: $0) }) { model.design.cornerSquareType = $0 }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Eye dot").font(.subheadline)
                            ShapeGallery(items: CornerDotType.allCases,
                                         selected: model.design.cornerDotType,
                                         title: { $0.title },
                                         glyph: { eyeDotGlyph(for: $0) }) { model.design.cornerDotType = $0 }
                        }
                        Toggle("Gradient", isOn: $model.design.gradientEnabled)
                        if model.design.gradientEnabled {
                            ColorPicker("Gradient end", selection: hexBinding(\.gradientColor2Hex), supportsOpacity: false)
                            Slider(value: $model.design.gradientRotation, in: 0...360, step: 15) {
                                Text("Gradient angle")
                            } minimumValueLabel: {
                                Text("0°")
                            } maximumValueLabel: {
                                Text("360°")
                            }
                        }
                        Toggle("Transparent background", isOn: $model.design.transparentBg)
                    } header: {
                        Text("Module style")
                    } footer: {
                        if model.design.dotType == .dots || model.design.transparentBg {
                            Text("Stylized modules trade ink for looks — the scanability score reflects the cost. Test with a real camera before printing.")
                        } else {
                            Text("Rounded shapes keep nearly full ink coverage and scan like square modules.")
                        }
                    }
                }

                Section("Reliability") {
                    if model.design.symbology == .qr {
                        Picker("Error correction", selection: $model.design.errorLevel) {
                            ForEach(ErrorLevel.allCases) { level in
                                Text("\(level.rawValue) — \(level.recoveryPercent)% recovery").tag(level)
                            }
                        }
                    }
                    Stepper("Quiet zone: \(model.design.quietModules) modules", value: $model.design.quietModules, in: 0...10)
                    if model.design.quietModules < 4 {
                        Text("ISO/IEC 18004 requires a 4-module quiet zone.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Stepper("Export size: \(model.design.exportSize)px", value: $model.design.exportSize, in: 256...4096, step: 256)
                }

                // Center logo is only safe on 2D symbologies with real error
                // correction — occluding a linear code kills it, so the
                // section disappears there instead of allowing a bad design.
                if model.design.symbology.carriesRichPayload {
                    Section("Center logo") {
                        let hasLogo = model.design.logoPNG != nil
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Label(hasLogo ? "Replace logo" : "Choose logo", systemImage: "photo")
                        }
                        if model.design.logoPNG != nil {
                            // Capped at 35% — RoundTripTests measured decode
                            // failure beginning at 40% even at EC-H.
                            Slider(value: $model.design.logoScale, in: 0.1...0.35) {
                                Text("Logo scale")
                            } minimumValueLabel: {
                                Text("10%")
                            } maximumValueLabel: {
                                Text("35%")
                            }
                            Button("Remove logo", role: .destructive) {
                                model.design.logoPNG = nil
                            }
                        }
                    }
                }

                Section {
                    // Disabled rather than silently ignored: the renderer drops
                    // the band when the background is transparent.
                    Toggle("Context band", isOn: $model.design.ctaEnabled)
                        .disabled(model.design.transparentBg)
                    if model.design.ctaEnabled, !model.design.transparentBg {
                        TextField("Scan to view menu", text: $model.design.ctaText)
                    }
                } footer: {
                    if model.design.transparentBg {
                        Text("Unavailable while the background is transparent — the band needs something to print on.")
                    } else {
                        Text("Prints a strip under the code: your call-to-action plus the destination, so people know what they're scanning before they scan it.")
                    }
                }
            }
            .navigationTitle("Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.designSheetPresented = false }
                }
            }
            .onChange(of: logoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Downscale large logos — 512px is plenty for a QR center.
                        if let img = UIImage(data: data),
                           let small = img.preparingThumbnail(of: CGSize(width: 512, height: 512)),
                           let png = small.pngData() {
                            model.design.logoPNG = png
                        } else {
                            model.design.logoPNG = data
                        }
                    }
                }
            }
        }
    }

    private func hexBinding(_ keyPath: WritableKeyPath<DesignOptions, String>) -> Binding<Color> {
        Binding(
            get: { Color(UIColor(hex: model.design[keyPath: keyPath])) },
            set: { model.design[keyPath: keyPath] = UIColor($0).hexString }
        )
    }
}

// MARK: - Design sheet helpers

/// The sheet's own live preview: every tap on a theme, shape or color is
/// reflected here instantly — design decisions are never blind.
private struct DesignPreviewCell: View {
    @Bindable var model: AppModel
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 44))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 150, height: 150)
            if !model.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(model.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: model.design) { await render() }
        .task(id: model.content) { await render() }
    }

    /// Debounced and awaited. Dragging the gradient slider previously started
    /// one detached render per step, none of them cancellable.
    private func render() async {
        if image != nil {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
        }
        let payload = model.payload
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            image = nil
            return
        }
        var design = model.design
        design.exportSize = 512
        let rendered = await Task.detached(priority: .userInitiated) {
            QRRenderer.image(payload: payload, design: design)
        }.value
        guard !Task.isCancelled else { return }
        image = rendered
    }
}

/// One-tap curated looks, shown as the actual code rendered with each
/// theme — you pick the result, not a name.
private struct ThemeGallery: View {
    @Bindable var model: AppModel
    @State private var thumbs: [String: UIImage] = [:]
    // Scales with the caption underneath instead of clipping it.
    @ScaledMetric(relativeTo: .caption2) private var thumb = 76

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DesignPreset.allCases) { preset in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { preset.apply(to: &model.design) }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                if let img = thumbs[preset.id] {
                                    Image(uiImage: img)
                                        .resizable()
                                        // Rendered at 256px and shown at ~228px:
                                        // a non-integer nearest-neighbour
                                        // downscale drops whole module rows.
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .padding(6)
                                }
                            }
                            .frame(width: thumb, height: thumb)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(preset.matches(model.design) ? Color.accentColor : .clear, lineWidth: 2)
                            )
                            Text(preset.title)
                                .font(.caption2)
                                .foregroundStyle(preset.matches(model.design) ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Theme: \(preset.title)")
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
        .task(id: model.payload) { renderThumbs() }
    }

    private func renderThumbs() {
        // Empty payloads still deserve informative thumbnails — a neutral
        // example, not a branded URL for a domain that does not exist.
        let payload = model.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "https://example.com" : model.payload
        Task.detached(priority: .userInitiated) {
            var map: [String: UIImage] = [:]
            for preset in DesignPreset.allCases {
                var d = DesignOptions()
                preset.apply(to: &d)
                d.exportSize = 256
                map[preset.id] = QRRenderer.image(payload: payload, design: d)
            }
            await MainActor.run { thumbs = map }
        }
    }
}

/// A horizontal row of visual swatches — the shape itself is the icon.
private struct ShapeGallery<Item: Identifiable & Hashable, Glyph: View>: View {
    let items: [Item]
    let selected: Item
    let title: (Item) -> String
    let glyph: (Item) -> Glyph
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy(duration: 0.2)) { onSelect(item) }
                        } label: {
                            VStack(spacing: 6) {
                                glyph(item)
                                    .foregroundStyle(selected == item ? Color.accentColor : Color.primary.opacity(0.7))
                                    .frame(width: 26, height: 26)
                                    .frame(width: 52, height: 52)
                                    .background(
                                        selected == item
                                            ? Color.accentColor.opacity(0.12)
                                            : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(selected == item ? Color.accentColor : .clear, lineWidth: 2)
                                    )
                                Text(title(item))
                                    .font(.caption2)
                                    .foregroundStyle(selected == item ? Color.accentColor : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            // A selection made elsewhere (e.g. a Theme) must be VISIBLE here —
            // scroll the selected swatch into view so theme and manual
            // controls never disagree silently.
            .onAppear { proxy.scrollTo(selected.id, anchor: .center) }
            .onChange(of: selected) { _, newValue in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(newValue.id, anchor: .center) }
            }
        }
    }
}

/// The classy teardrop as a SwiftUI shape — same geometry as the renderer,
/// so the swatch previews the real thing.
/// Gallery glyph for the fluid style: two fused blobs, echoing how
/// neighbor-aware modules merge into continuous rounded lines.
private struct FluidGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.height * 0.34
        let c1 = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.midY)
        let c2 = CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.midY)
        var p = Path()
        p.addArc(center: c1, radius: r, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.addArc(center: c2, radius: r, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// A leaf: two opposite corners rounded at half the side. That is the silhouette
/// a Classy module takes once a neighbour holds its other two corners square.
private struct LeafGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width * 0.5
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

extension DesignSheet {
    @ViewBuilder
    fileprivate func dotGlyph(for type: DotType) -> some View {
        switch type {
        case .square: RoundedRectangle(cornerRadius: 2, style: .continuous).fill()
        case .rounded: RoundedRectangle(cornerRadius: 8, style: .continuous).fill()
        case .extraRounded: RoundedRectangle(cornerRadius: 14, style: .continuous).fill()
        case .dots: Circle().fill()
        case .classy: LeafGlyphShape().fill()
        case .classyRounded: RoundedRectangle(cornerRadius: 22, style: .continuous).fill()
        case .fluid: FluidGlyphShape().fill()
        }
    }

    @ViewBuilder
    fileprivate func eyeFrameGlyph(for type: CornerSquareType) -> some View {
        switch type {
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(lineWidth: 4)
        case .extraRounded:
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(lineWidth: 4)
        case .dot:
            Circle().stroke(lineWidth: 4)
        }
    }

    @ViewBuilder
    fileprivate func eyeDotGlyph(for type: CornerDotType) -> some View {
        switch type {
        case .square:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill()
                .padding(4)
        case .dot:
            Circle().fill().padding(4)
        }
    }
}

/// System contact picker, out of process: no Contacts permission prompt,
/// the app receives only the single card the user taps.
private struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void
        init(onPick: @escaping (CNContact) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}
