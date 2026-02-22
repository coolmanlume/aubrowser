// AU Browser/Views/Gallery/PluginGridView.swift

import AUBrowserCore
import SwiftUI

/// Adaptive grid of `PluginCardItem`s.
///
/// During an active scan, only cards that have already been processed
/// (or are currently being captured) are shown, so the grid fills
/// progressively rather than flooding with 200+ placeholder cards at once.
/// When no scan is running all cards are visible.
struct PluginGridView: View {

    @Binding var selectedIds: Set<String>
    var onPluginSelected: (String) -> Void = { _ in }

    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 220), spacing: 14)]

    /// Rows visible right now. During scanning: only processed + in-progress cards.
    /// At rest: everything.
    private var visibleRows: [PluginRow] {
        guard scanManager.isScanning else { return store.rows }
        return store.rows.filter {
            $0.thumbnail != nil                              ||
            scanManager.processedIds.contains($0.id)        ||
            scanManager.progress.inProgress.contains($0.id)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(visibleRows) { row in
                    PluginCardItem(
                        row: row,
                        isSelected: selectedIds.contains(row.id),
                        onSelect: {
                            selectedIds = []
                            onPluginSelected(row.id)
                        },
                        onToggleSelection: {
                            if selectedIds.contains(row.id) {
                                selectedIds.remove(row.id)
                            } else {
                                selectedIds.insert(row.id)
                            }
                        }
                    )
                }
            }
            .padding(16)
            .animation(.default, value: visibleRows.map(\.id))
        }
    }
}
