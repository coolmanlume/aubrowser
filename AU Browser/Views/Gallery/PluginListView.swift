// AU Browser/Views/Gallery/PluginListView.swift

import AppKit
import AUBrowserCore
import SwiftUI

/// Sortable table view of all visible plugins.
struct PluginListView: View {

    @Binding var selectedIds: Set<String>
    var onPluginSelected: (String) -> Void = { _ in }

    @EnvironmentObject private var store: PluginStore
    @State private var tableSortOrder: [KeyPathComparator<PluginRow>] = [
        .init(\.plugin.name, order: .forward)
    ]

    var body: some View {
        Table(store.rows, selection: $selectedIds, sortOrder: $tableSortOrder) {
            // Thumbnail column — view only, not sortable
            TableColumn("") { row in
                ThumbnailCell(thumbnail: row.thumbnail)
            }
            .width(52)

            TableColumn("Name", value: \.plugin.name)
                .width(min: 160, ideal: 200)

            TableColumn("Manufacturer", value: \.plugin.manufacturer)
                .width(min: 120, ideal: 150)

            TableColumn("Type", value: \.plugin.type)
                .width(min: 80, ideal: 100)

            TableColumn("Version", value: \.plugin.version)
                .width(min: 60, ideal: 80)

            TableColumn("Installed", value: \.plugin.installDate) { row in
                Text(row.plugin.installDate, style: .date)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first,
               let row = store.rows.first(where: { $0.id == id }) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(row.plugin.bundlePath,
                                                  inFileViewerRootedAtPath: "")
                }
            }
        }
        .onChange(of: tableSortOrder) { _, order in
            guard let first = order.first else { return }
            var f = store.filter

            switch first.keyPath {
            case \PluginRow.plugin.name:         f.sortOrder = .name
            case \PluginRow.plugin.manufacturer: f.sortOrder = .manufacturer
            case \PluginRow.plugin.type:         f.sortOrder = .type
            case \PluginRow.plugin.version:      f.sortOrder = .name   // fallback
            case \PluginRow.plugin.installDate:  f.sortOrder = .installDate
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
