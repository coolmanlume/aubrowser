// AU Browser/Views/Toolbar/ToolbarSearchBar.swift

import AUBrowserCore
import SwiftUI

/// Compact search field that lives in the toolbar.
/// Feeds the search query through `PluginStore.applyFilter`, which debounces it.
struct ToolbarSearchBar: View {

    @EnvironmentObject private var store: PluginStore
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Search plugins…", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .onChange(of: text) { _, newValue in
                    var f = store.filter
                    f.searchQuery = newValue
                    store.applyFilter(f)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    var f = store.filter
                    f.searchQuery = ""
                    store.applyFilter(f)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Keep text in sync if the filter is cleared externally (e.g. "Clear all filters")
        .onReceive(store.$filter) { filter in
            if filter.searchQuery != text { text = filter.searchQuery }
        }
    }
}
