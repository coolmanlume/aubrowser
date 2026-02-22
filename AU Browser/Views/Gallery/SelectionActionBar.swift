// AU Browser/Views/Gallery/SelectionActionBar.swift

import AUBrowserCore
import SwiftUI

/// Bottom bar that appears when one or more plugin cards are selected.
/// Provides batch Like All, Rescan All, and Deselect actions.
struct SelectionActionBar: View {

    @Binding var selectedIds: Set<String>

    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    var body: some View {
        HStack(spacing: 16) {
            Text("\(selectedIds.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                Task { await store.addToFavorites(pluginIds: selectedIds) }
            } label: {
                Label("Like All", systemImage: "heart.fill")
            }

            Button {
                let plugins = store.rows
                    .filter { selectedIds.contains($0.id) }
                    .map(\.plugin)
                scanManager.rescan(plugins)
            } label: {
                Label("Rescan All", systemImage: "arrow.clockwise")
            }

            Button {
                selectedIds = []
            } label: {
                Label("Deselect", systemImage: "xmark")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
