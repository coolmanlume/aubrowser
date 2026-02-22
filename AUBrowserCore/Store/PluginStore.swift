// AUBrowserCore/Store/PluginStore.swift

import Combine
import Foundation
import GRDB

// MARK: - PluginRow

/// A fully denormalised row ready for the UI — plugin data joined with its
/// optional thumbnail and user metadata.
public struct PluginRow: Identifiable, Equatable {
    public var plugin:    Plugin
    public var thumbnail: Thumbnail?
    public var userData:  UserData?

    public var id: String { plugin.id }
}

// MARK: - PluginStore

/// The single query layer between the SQLite database and SwiftUI views.
///
/// Responsibilities:
/// - Keeps an in-memory snapshot of all non-removed plugins (updated automatically
///   via GRDB `ValueObservation` whenever the scan queue writes new data).
/// - Applies `PluginFilter` in memory — type, manufacturer, tags, favorites, search.
/// - Debounces search-query changes (80 ms) so keystrokes don't hammer the filter.
/// - Exposes write helpers (toggle favorite, update tags/notes) that produce
///   immediate DB writes; the observation loop picks up the change and refreshes `rows`.
/// - Provides sidebar data: the unique manufacturer and tag lists derived from the snapshot.
@MainActor
public final class PluginStore: ObservableObject {

    // MARK: - Published — consumed by SwiftUI

    /// Filtered and sorted rows ready for the gallery / list view.
    @Published public private(set) var rows: [PluginRow] = []

    /// Unique manufacturer names present in the DB (drives the sidebar).
    @Published public private(set) var manufacturers: [String] = []

    /// Unique user-created tag strings across all plugins (drives the sidebar tag list).
    @Published public private(set) var allTags: [String] = []

    // MARK: - Filter

    /// Setting this property immediately re-applies all dimensions except the search
    /// query, which is debounced by 80 ms.  Set via `applyFilter(_:)` from the UI.
    @Published public private(set) var filter: PluginFilter = .empty

    /// Update the current filter.  Search-query changes are debounced; all other
    /// dimension changes (type, manufacturer, sort…) take effect immediately.
    public func applyFilter(_ newFilter: PluginFilter) {
        let searchChanged = newFilter.searchQuery != filter.searchQuery
        filter = newFilter

        if searchChanged {
            scheduleSearch()
        } else {
            refilter()
        }
    }

    /// Convenience — resets every filter dimension back to defaults.
    public func clearFilter() {
        applyFilter(.empty)
    }

    // MARK: - Private state

    private let db: DatabaseSetup

    /// Full unfiltered snapshot from the last DB observation tick.
    private var snapshot: [PluginRow] = []

    /// The running GRDB observation; kept alive for the lifetime of the store.
    private var observationTask: Task<Void, Never>?

    /// Running debounce task for the search query.
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    public init(db: DatabaseSetup = .shared) {
        self.db = db
        startObservation()
    }

    deinit {
        observationTask?.cancel()
        debounceTask?.cancel()
    }

    // MARK: - GRDB observation

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> ([Plugin], [Thumbnail], [UserData]) in
            let plugins  = try Plugin
                .filter(Column("isRemoved") == false)
                .fetchAll(db)
            let thumbs   = try Thumbnail.fetchAll(db)
            let userData = try UserData.fetchAll(db)
            return (plugins, thumbs, userData)
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // `values(in:)` delivers the first value immediately (synchronous fetch),
                // then re-fires whenever any observed table changes.
                for try await (plugins, thumbs, userData) in observation.values(in: db.dbPool) {
                    guard !Task.isCancelled else { return }
                    processSnapshot(plugins: plugins, thumbs: thumbs, userData: userData)
                }
            } catch {
                // Observation errors are non-fatal; the store simply stops refreshing.
            }
        }
    }

    private func processSnapshot(
        plugins:  [Plugin],
        thumbs:   [Thumbnail],
        userData: [UserData]
    ) {
        let thumbIndex = Dictionary(thumbs.map    { ($0.pluginId, $0) }, uniquingKeysWith: { a, _ in a })
        let userIndex  = Dictionary(userData.map  { ($0.pluginId, $0) }, uniquingKeysWith: { a, _ in a })

        snapshot = plugins.map { plugin in
            PluginRow(
                plugin:    plugin,
                thumbnail: thumbIndex[plugin.id],
                userData:  userIndex[plugin.id]
            )
        }

        // Derive sidebar data from the full snapshot (not the filtered view)
        manufacturers = Array(Set(snapshot.map(\.plugin.manufacturer))).sorted()
        allTags       = Array(Set(snapshot.flatMap { $0.userData?.tagList ?? [] })).sorted()

        refilter()
    }

    // MARK: - Filter application

    private func scheduleSearch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)  // 80 ms
            guard !Task.isCancelled, let self else { return }
            refilter()
        }
    }

    private func refilter() {
        var result = snapshot

        // Plugin type
        if let type = filter.pluginType {
            result = result.filter { $0.plugin.type == type.rawValue }
        }

        // Manufacturer (multi-select OR)
        if !filter.manufacturers.isEmpty {
            result = result.filter { filter.manufacturers.contains($0.plugin.manufacturer) }
        }

        // Tags (plugin must have at least one of the selected tags)
        if !filter.tags.isEmpty {
            result = result.filter { row in
                let pluginTags = Set(row.userData?.tagList ?? [])
                return !filter.tags.isDisjoint(with: pluginTags)
            }
        }

        // Favorites only
        if filter.favoritesOnly {
            result = result.filter { $0.userData?.isFavorite == true }
        }

        // Search — case-insensitive substring across name, manufacturer, type
        if !filter.searchQuery.isEmpty {
            let query = filter.searchQuery.lowercased()
            result = result.filter { row in
                row.plugin.name.lowercased().contains(query)         ||
                row.plugin.manufacturer.lowercased().contains(query) ||
                row.plugin.type.lowercased().contains(query)
            }
        }

        // Sort
        result.sort { a, b in
            switch filter.sortOrder {
            case .name:
                let cmp = a.plugin.name.localizedCompare(b.plugin.name)
                return filter.sortAscending
                    ? cmp == .orderedAscending
                    : cmp == .orderedDescending

            case .manufacturer:
                let cmp = a.plugin.manufacturer.localizedCompare(b.plugin.manufacturer)
                return filter.sortAscending
                    ? cmp == .orderedAscending
                    : cmp == .orderedDescending

            case .type:
                let typeCmp = a.plugin.type.localizedCompare(b.plugin.type)
                if typeCmp != .orderedSame {
                    return filter.sortAscending
                        ? typeCmp == .orderedAscending
                        : typeCmp == .orderedDescending
                }
                // Within the same type, break ties by name
                return a.plugin.name.localizedCompare(b.plugin.name) == .orderedAscending

            case .installDate:
                return filter.sortAscending
                    ? a.plugin.installDate < b.plugin.installDate
                    : a.plugin.installDate > b.plugin.installDate

            case .favorites:
                // Favorited plugins always sort to the top; break ties by name
                let aFav = a.userData?.isFavorite ?? false
                let bFav = b.userData?.isFavorite ?? false
                if aFav != bFav { return aFav }
                return a.plugin.name.localizedCompare(b.plugin.name) == .orderedAscending
            }
        }

        rows = result
    }

    // MARK: - User data writes

    /// Toggles `isFavorite` for the given plugin, creating a `UserData` row if needed.
    public func toggleFavorite(pluginId: String) async {
        await writeUserData(pluginId: pluginId) { $0.isFavorite.toggle() }
    }

    /// Sets `isFavorite = true` for every plugin in the set (single DB transaction).
    public func addToFavorites(pluginIds: Set<String>) async {
        do {
            try await db.dbPool.write { db in
                for id in pluginIds {
                    var ud = (try UserData.fetchOne(db, key: id)) ?? UserData(pluginId: id)
                    ud.isFavorite = true
                    try ud.save(db)
                }
            }
        } catch {}
    }

    /// Replaces the tag list for the given plugin.
    public func setTags(pluginId: String, tags: [String]) async {
        await writeUserData(pluginId: pluginId) { $0.setTags(tags) }
    }

    /// Updates the free-text notes for the given plugin.
    public func setNotes(pluginId: String, notes: String?) async {
        await writeUserData(pluginId: pluginId) { $0.notes = notes }
    }

    /// Generic helper — fetches (or creates) the `UserData` row, applies `mutate`, saves.
    private func writeUserData(
        pluginId: String,
        mutate: (inout UserData) -> Void
    ) async {
        do {
            try await db.dbPool.write { db in
                var ud = (try UserData.fetchOne(db, key: pluginId))
                    ?? UserData(pluginId: pluginId)
                mutate(&ud)
                try ud.save(db)
            }
        } catch {}
        // The ValueObservation fires automatically and refreshes `rows`.
    }

    // MARK: - Convenience reads

    /// Returns the current `PluginRow` for a given id from the unfiltered snapshot,
    /// useful for populating detail popovers without requiring the plugin to be visible.
    public func row(for pluginId: String) -> PluginRow? {
        snapshot.first { $0.id == pluginId }
    }

    /// Returns all scan records for a plugin, newest first.
    public func scanHistory(for pluginId: String) async -> [ScanRecord] {
        (try? await db.dbPool.read { db in
            try ScanRecord
                .filter(Column("pluginId") == pluginId)
                .order(Column("attemptedAt").desc)
                .fetchAll(db)
        }) ?? []
    }
}
