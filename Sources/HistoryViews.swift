import SwiftUI

/// Saved codes.
///
/// A list rather than a grid: a code is identified by what it carries and when
/// it was saved, and a row says both without making anyone open it to find out.
struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    private var matches: [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return model.history }
        return model.history.filter {
            PayloadBuilder.summarize($0.content).lowercased().contains(needle)
                || $0.content.type.title.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "square.grid.2x2",
                        description: Text("Codes you share or export land here for one-tap re-editing.")
                    )
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(matches) { entry in
                            // A Button rather than onTapGesture with an
                            // .isButton trait: the trait made VoiceOver announce
                            // it correctly, but Switch Control and Full Keyboard
                            // Access could not activate it.
                            Button {
                                Haptics.selection()
                                model.restore(entry)
                            } label: {
                                LibraryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.deleteHistory(entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    // The search field belongs to the list that it filters, not
                    // to the container: attached outside the scroll view it
                    // rendered as a detached band above the rows.
                    // Placement is explicit: the default put the field at the
                    // bottom of the screen on this OS version, where the custom
                    // bar sits, leaving it half-hidden behind the tabs.
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "What a code carries")
                    .scrollContentBackground(.hidden)
                    .background(Theme.page)
                }
            }
            // No dismissal: this is a destination, and restoring a code moves to
            // the studio through the bar rather than closing anything.
            .navigationTitle("Library")
        }
    }
}

/// One saved code: the symbol, what it carries, and when it was saved.
private struct LibraryRow: View {
    let entry: HistoryEntry
    @State private var thumbnail: UIImage?

    private var kind: String {
        entry.design.symbology.carriesRichPayload
            ? entry.content.type.title
            : entry.design.symbology.title
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.control, style: .continuous)
                    .fill(Theme.paper)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        // Rendered at 240px for a 44pt row: an upscale, so
                        // nearest-neighbour would show unevenly sized modules.
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(3)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.control, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(PayloadBuilder.summarize(entry.content))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Theme.tight)

            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .task {
            let payload = PayloadBuilder.payload(for: entry.content, symbology: entry.design.symbology)
            var design = entry.design
            design.exportSize = 240
            thumbnail = await Task.detached(priority: .utility) {
                QRRenderer.image(payload: payload, design: design)
            }.value
        }
        // The enclosing Button supplies the button trait; this label only has to
        // say what the code is and what tapping it does.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind) code, \(PayloadBuilder.summarize(entry.content)). Opens in the studio.")
    }
}
