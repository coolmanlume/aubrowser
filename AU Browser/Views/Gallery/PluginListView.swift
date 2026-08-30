// AU Browser/Views/Gallery/PluginListView.swift

import AppKit
import AUBrowserCore
import SwiftUI

/// Sortable table view of all visible plugins.
struct PluginListView: View {

    @Binding var selectedIds: Set<String>
    var onPluginSelected: (String) -> Void = { _ in }

    @EnvironmentObject private var store: PluginStore
    @State private var tableSortOrder: [KeyPathComparator<PluginGroup>] = [
        .init(\.displayName, order: .forward)
    ]

    var body: some View {
        Table(store.groupedRows, selection: $selectedIds, sortOrder: $tableSortOrder) {
            // Thumbnail column — view only, not sortable
            TableColumn("") { group in
                ThumbnailCell(thumbnail: group.primary.thumbnail)
            }
            .width(52)

            TableColumn("Name", value: \.displayName)
                .width(min: 160, ideal: 200)

            TableColumn("Manufacturer", value: \.manufacturer)
                .width(min: 120, ideal: 150)

            TableColumn("Type", value: \.primary.plugin.type)
                .width(min: 80, ideal: 100)

            TableColumn("Version", value: \.primary.plugin.version)
                .width(min: 60, ideal: 80)

            TableColumn("Installed", value: \.primary.plugin.installDate) { group in
                Text(group.primary.plugin.installDate, style: .date)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Versions", value: \.variants.count) { group in
                if group.hasMultipleVariants {
                    Text("\(group.variants.count)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(60)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first,
               let group = store.groupedRows.first(where: { $0.id == id }) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(group.primary.plugin.bundlePath,
                                                  inFileViewerRootedAtPath: "")
                }
            }
        }
        .onChange(of: tableSortOrder) { _, order in
            guard let first = order.first else { return }
            var f = store.filter

            switch first.keyPath {
            case \PluginGroup.displayName:              f.sortOrder = .name
            case \PluginGroup.manufacturer:              f.sortOrder = .manufacturer
            case \PluginGroup.primary.plugin.type:       f.sortOrder = .type
            case \PluginGroup.primary.plugin.version:    f.sortOrder = .name   // fallback
            case \PluginGroup.primary.plugin.installDate: f.sortOrder = .installDate
            default: break
            }

            f.sortAscending = first.order == .forward
            store.applyFilter(f)
        }
        .onKeyPress(.return) {
            // TODO: open detail for selected row
            return .ignored
        }
    }
}

// MARK: - Thumbnail cell

private struct ThumbnailCell: View {

    let thumbnail: Thumbnail?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.separatorColor).opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.quaternary)
                            .imageScale(.small)
                    )
            }
        }
        .task(id: thumbnail?.jpegPath) {
            image = nil
            if let t = thumbnail {
                image = await ThumbnailCache.shared.image(for: t)
            }
        }
    }
}
