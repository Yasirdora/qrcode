import SwiftUI

/// Saved designs — thumbnails render from the stored ContentState + DesignOptions,
/// tap to re-edit, swipe or context menu to delete.
struct HistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Codes you share or export land here for one-tap re-editing.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(model.history) { entry in
                                HistoryCard(entry: entry)
                                    .onTapGesture {
                                        Haptics.selection()
                                        model.restore(entry)
                                        dismiss()
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            model.deleteHistory(entry.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close history")
                }
            }
        }
    }
}

private struct HistoryCard: View {
    let entry: HistoryEntry
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .aspectRatio(1, contentMode: .fit)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(12)
                }
            }
            HStack {
                Text(entry.design.symbology.carriesRichPayload ? entry.content.type.title : entry.design.symbology.title)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
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
        .panel(cornerRadius: 18)
        .task {
            let payload = PayloadBuilder.payload(for: entry.content, symbology: entry.design.symbology)
            var thumbDesign = entry.design
            thumbDesign.exportSize = 300
            thumbnail = await Task.detached(priority: .utility) {
                QRRenderer.image(payload: payload, design: thumbDesign)
            }.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.content.type.title) code, \(PayloadBuilder.summarize(entry.content)). Double-tap to re-edit.")
        .accessibilityAddTraits(.isButton)
    }
}
