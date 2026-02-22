// AUBrowserCore/Database/Models/UserData.swift

import Foundation
import GRDB

/// Stores user-supplied metadata for a plugin.
///
/// One-to-one with Plugin. A row is created (with defaults) on first interaction
/// so that we never have to handle nil for basic fields like isFavorite.
public struct UserData: Codable, Equatable, FetchableRecord, PersistableRecord {

    // MARK: - Stored properties

    /// FK → Plugin.id (also the PK — one UserData per plugin).
    public var pluginId: String

    public var isFavorite: Bool

    /// Comma-separated tag strings, e.g. "synth,bass,retro".
    /// Use `tagList` for the parsed array.
    public var tags: String

    public var notes: String?

    /// Optional explicit position in a custom sort. nil = follows current sort order.
    public var userSortIndex: Int?

    // MARK: - GRDB

    public static let databaseTableName = "userData"

    // MARK: - Init

    public init(
        pluginId: String,
        isFavorite: Bool = false,
        tags: String = "",
        notes: String? = nil,
        userSortIndex: Int? = nil
    ) {
        self.pluginId = pluginId
        self.isFavorite = isFavorite
        self.tags = tags
        self.notes = notes
        self.userSortIndex = userSortIndex
    }

    // MARK: - Helpers

    /// The `tags` string split and trimmed into individual tag values.
    public var tagList: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Rebuilds the comma-separated `tags` string from an array.
    public mutating func setTags(_ list: [String]) {
        tags = list
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    /// Returns a copy of `self` with the given tag toggled on or off.
    public func togglingTag(_ tag: String) -> UserData {
        var copy = self
        var list = tagList
        if let idx = list.firstIndex(of: tag) {
            list.remove(at: idx)
        } else {
            list.append(tag)
        }
        copy.setTags(list)
        return copy
    }
}
