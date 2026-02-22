// AU Browser/Views/Sidebar/SidebarView.swift

import AppKit
import AUBrowserCore
import SwiftUI

/// The left sidebar with type, manufacturer and tag filters.
///
/// Single-click selects exclusively; Command-click toggles in manufacturer
/// and tag lists (multi-select).
struct SidebarView: View {

    @EnvironmentObject private var store: PluginStore

    var body: some View {
        List {
            typeSection
            manufacturerSection
            tagsSection
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if store.filter.isActive { clearPill }
        }
    }

    // MARK: - Type section

    private var typeSection: some View {
        Section("Type") {
            typeRow(label: "All", type: nil)
            ForEach(PluginType.allCases) { type in
                typeRow(label: type.displayName, type: type)
            }
        }
    }

    private func typeRow(label: String, type: PluginType?) -> some View {
        let selected = store.filter.pluginType == type
        return FilterRow(label: label, isSelected: selected)
            .onTapGesture {
                var f = store.filter
                f.pluginType = (selected && type != nil) ? nil : type
                store.applyFilter(f)
            }
    }

    // MARK: - Manufacturer section

    private var manufacturerSection: some View {
        Section("Manufacturer") {
            ForEach(store.manufacturers, id: \.self) { mfr in
                let selected = store.filter.manufacturers.contains(mfr)
                FilterRow(label: mfr, isSelected: selected)
                    .onTapGesture {
                        var f = store.filter
                        if NSEvent.modifierFlags.contains(.command) {
                            // Command-click: toggle this one, keep others
                            if selected { f.manufacturers.remove(mfr) }
                            else         { f.manufacturers.insert(mfr) }
                        } else {
                            // Regular click: exclusive select / deselect
                            f.manufacturers = selected ? [] : [mfr]
                        }
                        store.applyFilter(f)
                    }
            }
        }
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        Section("Tags") {
            // Favorites shortcut
            let favSelected = store.filter.favoritesOnly
            FilterRow(label: "Favorites", isSelected: favSelected)
                .onTapGesture {
                    var f = store.filter
                    f.favoritesOnly.toggle()
                    store.applyFilter(f)
                }

            // User tags
            ForEach(store.allTags, id: \.self) { tag in
                let selected = store.filter.tags.contains(tag)
                FilterRow(label: tag, isSelected: selected)
                    .onTapGesture {
                        var f = store.filter
                        if NSEvent.modifierFlags.contains(.command) {
                            if selected { f.tags.remove(tag) }
                            else         { f.tags.insert(tag) }
                        } else {
                            f.tags = selected ? [] : [tag]
                        }
                        store.applyFilter(f)
                    }
            }
        }
    }

    // MARK: - Clear filters pill

    private var clearPill: some View {
        Button {
            store.clearFilter()
        } label: {
            Label("Clear all filters", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
