// AU Browser/ContentView.swift

import AUBrowserCore
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: PluginStore
    @EnvironmentObject private var scanManager: ScanQueueManager

    @State private var viewMode: ViewMode = .grid
    @State private var detailRow: PluginRow?
    @State private var selectedIds: Set<String> = []

    // Tracks whether we've kicked off the first scan this session
    @State private var didStartScan = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            PluginGalleryView(
                viewMode: viewMode,
                selectedIds: $selectedIds,
                onPluginSelected: { id in detailRow = store.row(for: id) }
            )
            .navigationTitle("AU Browser")
            .toolbar { toolbarContent }
        }
        .sheet(item: $detailRow) { row in
            PluginDetailPopover(row: row)
                .environmentObject(store)
                .environmentObject(scanManager)
        }
        .task { await startupScan() }
        .onReceive(NotificationCenter.default.publisher(for: .auBrowserRescanAll)) { _ in
            Task { await fullRescan() }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ToolbarSearchBar()
        }

        ToolbarItemGroup(placement: .automatic) {
            sortPicker
            sortDirectionButton
            Spacer()
            viewToggle
            if scanManager.isScanning || scanManager.canResume { ScanProgressBanner() }
        }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: Binding(
            get: { store.filter.sortOrder },
            set: { order in
                var f = store.filter
                f.sortOrder = order
                store.applyFilter(f)
            }
        )) {
            ForEach(SortOrder.allCases) { order in
                Text(order.displayName).tag(order)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 130)
        .help("Sort plugins")
    }

    private var sortDirectionButton: some View {
        Button {
            var f = store.filter
            f.sortAscending.toggle()
            store.applyFilter(f)
        } label: {
            Image(systemName: store.filter.sortAscending ? "arrow.up" : "arrow.down")
        }
        .help(store.filter.sortAscending ? "Sort ascending" : "Sort descending")
    }

    private var viewToggle: some View {
        Picker("View", selection: $viewMode) {
            ForEach(ViewMode.allCases) { mode in
                Image(systemName: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 70)
        .help("Switch between grid and list")
    }

    // MARK: - Startup

    private func startupScan() async {
        guard !didStartScan else { return }
        didStartScan = true

        let existing  = await DatabaseSetup.shared.fetchAllPlugins()
        let installed = await PluginEnumerator.enumerateInstalledPlugins(existingPlugins: existing)
        scanManager.startIncrementalScan(installedPlugins: installed)
    }

    private func fullRescan() async {
        let existing  = await DatabaseSetup.shared.fetchAllPlugins()
        let installed = await PluginEnumerator.enumerateInstalledPlugins(existingPlugins: existing)
        ThumbnailCache.shared.removeAll()
        scanManager.startFullRescan(installedPlugins: installed)
    }
}
