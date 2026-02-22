// AU Browser/Views/Gallery/PluginGalleryView.swift

import AUBrowserCore
import SwiftUI

/// Switches between the grid and list layout based on `viewMode`.
struct PluginGalleryView: View {

    let viewMode: ViewMode
    @Binding var selectedIds: Set<String>
    var onPluginSelected: (String) -> Void = { _ in }

    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    var body: some View {
        VStack(spacing: 0) {
            if scanManager.isScanning {
                ProgressView(value: scanManager.progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .animation(.easeInOut, value: scanManager.progress.fraction)
            }

            Group {
                if store.rows.isEmpty && !store.filter.isActive {
                    emptyState
                } else {
                    switch viewMode {
                    case .grid:
                        PluginGridView(
                            selectedIds: $selectedIds,
                            onPluginSelected: onPluginSelected
                        )
                    case .list:
                        PluginListView(
                            selectedIds: $selectedIds,
                            onPluginSelected: onPluginSelected
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !selectedIds.isEmpty {
                SelectionActionBar(selectedIds: $selectedIds)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("No plugins found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AU Browser will scan your installed Audio Units on first launch.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}
