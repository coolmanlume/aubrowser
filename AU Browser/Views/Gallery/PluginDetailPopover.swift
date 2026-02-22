// AU Browser/Views/Gallery/PluginDetailPopover.swift

import AppKit
import AUBrowserCore
import SwiftUI

/// Full-detail sheet shown when the user clicks a card or list row.
struct PluginDetailPopover: View {

    let row: PluginRow

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    // Local mutable state
    @State private var image: NSImage?
    @State private var isFavorite: Bool = false
    @State private var tagInput: String = ""
    @State private var notes: String = ""

    private var plugin: Plugin { row.plugin }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    thumbnailSection
                    metadataGrid
                    Divider()
                    tagsSection
                    notesSection
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
        .task(id: row.thumbnail?.jpegPath) {
            image = nil
            if let thumb = row.thumbnail { image = await ThumbnailCache.shared.image(for: thumb) }
        }
        .onAppear {
            isFavorite = row.userData?.isFavorite ?? false
            tagInput   = row.userData?.tags ?? ""
            notes      = row.userData?.notes ?? ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.title3.weight(.semibold))
                Text(plugin.manufacturer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            favoriteButton
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var favoriteButton: some View {
        Button {
            isFavorite.toggle()
            Task { await store.toggleFavorite(pluginId: plugin.id) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? Color.red : Color.secondary)
                .imageScale(.large)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
            } else {
                PlaceholderThumbnail()
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metadata

    private var metadataGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            metadataRow("Type",        plugin.pluginType?.displayName ?? plugin.type.capitalized)
            metadataRow("Version",     plugin.version)
            metadataRow("Installed",   plugin.installDate.formatted(.dateTime.day().month().year()))
            metadataRow("Last seen",   plugin.lastSeenDate.formatted(.dateTime.day().month().year()))
            GridRow {
                Text("Location")
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(plugin.bundlePath)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            // Display existing tags as chips
            if let tags = row.userData?.tagList, !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }

            // Comma-separated tag editor
            HStack {
                TextField("Add tags (comma-separated)…", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let tags = tagInput
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Task { await store.setTags(pluginId: plugin.id, tags: tags) }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextEditor(text: $notes)
                .font(.callout)
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor))
                )
                .onChange(of: notes) { _, newValue in
                    Task { await store.setNotes(pluginId: plugin.id, notes: newValue.isEmpty ? nil : newValue) }
                }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Rescan") { scanManager.rescan(plugin) }
                .buttonStyle(.bordered)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(16)
    }
}
