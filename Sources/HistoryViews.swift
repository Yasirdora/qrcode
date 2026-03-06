import SwiftUI

/// Saved codes — thumbnails render from the stored ContentState and
/// DesignOptions; tapping one opens it in the studio.
struct LibraryView: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Codes you share or export land here for one-tap re-editing.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(model.history) { entry in
                                // A real Button rather than onTapGesture plus an
                                // .isButton trait: VoiceOver announced that one
                                // correctly, but Switch Control and Full Keyboard
                                // Access could not activate it.
                                Button {
                                    Haptics.selection()
                                    model.restore(entry)
                                } label: {
                                    HistoryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        model.deleteHistory(entry.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(Theme.gutter)
                    }
                    .background(Theme.page)
                }
            }
            // No dismissal: this is a destination. Restoring a code moves to the
            // studio through the bar rather than closing anything.
            .navigationTitle("Library")
        }
    }
}

/// One saved code: the symbol, what it carries, and when it was saved.
private struct HistoryCard: View {
    let entry: HistoryEntry
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: Theme.tight) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.control, style: .continuous)
                    .fill(Theme.surface)
                    .aspectRatio(1, contentMode: .fit)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        // Rendered at 300px and shown at ~450px on a 3× screen,
                        // so this is an upscale: nearest-neighbour turns every
                        // module into a visible block of uneven size.
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(12)
                }
            }
            HStack {
                Text(entry.design.symbology.carriesRichPayload ? entry.content.type.title : entry.design.symbology.title)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceRaised, in: Capsule())
                Spacer()
                Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(PayloadBuilder.summarize(entry.content))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .panel(cornerRadius: Theme.card)
        .task {
            let payload = PayloadBuilder.payload(for: entry.content, symbology: entry.design.symbology)
            var thumbDesign = entry.design
            thumbDesign.exportSize = 300
            thumbnail = await Task.detached(priority: .utility) {
                QRRenderer.image(payload: payload, design: thumbDesign)
            }.value
        }
        // The enclosing Button supplies the button trait; the label only has to
        // say what the code is and what tapping it does.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.content.type.title) code, \(PayloadBuilder.summarize(entry.content)). Opens in the studio.")
    }
}
