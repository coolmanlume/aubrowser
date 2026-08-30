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

    /// Groups visible right now. During a library-wide (bulk) scan: only groups with
    /// at least one processed or in-progress variant, so the grid fills in
    /// progressively instead of flashing hundreds of not-yet-captured cards. A
    /// targeted rescan of one plugin or a selection never hides the rest of the
    /// library — only `isBulkScan` gates this, not `isScanning` alone.
    private var visibleGroups: [PluginGroup] {
        guard scanManager.isScanning, scanManager.isBulkScan else { return store.groupedRows }
        return store.groupedRows.filter { group in
            group.variants.contains {
                $0.row.thumbnail != nil                              ||
                scanManager.processedIds.contains($0.id)             ||
                scanManager.progress.inProgress.contains($0.id)
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(visibleGroups) { group in
                    PluginCardItem(
                        group: group,
                        isSelected: selectedIds.contains(group.id),
                        onSelect: {
                            selectedIds = []
                            onPluginSelected(group.id)
                        },
                        onToggleSelection: {
                            if selectedIds.contains(group.id) {
                                selectedIds.remove(group.id)
                            } else {
                                selectedIds.insert(group.id)
                            }
                        }
                    )
                }
            }
            .padding(16)
            .animation(.default, value: visibleGroups.map(\.id))
        }
    }
}
