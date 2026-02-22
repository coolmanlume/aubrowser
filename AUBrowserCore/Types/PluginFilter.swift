// AUBrowserCore/Types/PluginFilter.swift

import Foundation

// MARK: - PluginType

/// The four AU component categories shown in the sidebar.
public enum PluginType: String, CaseIterable, Identifiable, Codable {
    case instrument
    case effect
    case midi
    case generator

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .instrument: return "Instruments"
        case .effect:     return "Effects"
        case .midi:       return "MIDI"
        case .generator:  return "Generators"
        }
    }
}

// MARK: - PluginFilter

/// Aggregates every active filter / sort the UI can apply.
/// Built fresh from the sidebar + toolbar state and handed to PluginStore.
public struct PluginFilter: Equatable {

    /// Restrict to a single AU type category. `nil` means "All".
    public var pluginType: PluginType?

    /// Restrict to these manufacturers. Empty means "All".
    public var manufacturers: Set<String>

    /// Restrict to plugins that carry at least one of these tags.
    public var tags: Set<String>

    /// When `true`, only return plugins whose UserData.isFavorite == 1.
    public var favoritesOnly: Bool

    /// Live search string (debounced by the UI layer).
    public var searchQuery: String

    /// Column to sort results by.
    public var sortOrder: SortOrder

    /// Sort direction.
    public var sortAscending: Bool

    public init(
        pluginType: PluginType? = nil,
        manufacturers: Set<String> = [],
        tags: Set<String> = [],
        favoritesOnly: Bool = false,
        searchQuery: String = "",
        sortOrder: SortOrder = .name,
        sortAscending: Bool = true
    ) {
        self.pluginType = pluginType
        self.manufacturers = manufacturers
        self.tags = tags
        self.favoritesOnly = favoritesOnly
        self.searchQuery = searchQuery
        self.sortOrder = sortOrder
        self.sortAscending = sortAscending
    }

    /// `true` when any non-default filter is set (drives "Clear all filters" pill).
    public var isActive: Bool {
        pluginType != nil
            || !manufacturers.isEmpty
            || !tags.isEmpty
            || favoritesOnly
            || !searchQuery.isEmpty
    }

    /// Convenience — a fresh filter with no constraints, sorted by name ascending.
    public static let empty = PluginFilter()
}
