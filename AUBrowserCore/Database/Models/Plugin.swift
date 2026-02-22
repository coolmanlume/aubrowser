// AUBrowserCore/Database/Models/Plugin.swift

import Foundation
import GRDB

/// Represents a single installed Audio Unit component.
///
/// `id` is derived from the bundle ID + component subtype hash so that
/// distinct components inside the same plugin bundle each get their own row.
public struct Plugin: Codable, Equatable, FetchableRecord, PersistableRecord {

    // MARK: - Stored properties

    /// Primary key. Format: "<bundleID>_<subtypeHex>"
    public var id: String

    public var name: String
    public var manufacturer: String

    /// "instrument" | "effect" | "midi" | "generator"
    public var type: String

    /// AU four-char component subtype code (stored as Int for SQLite compatibility).
    public var subtype: Int

    /// Absolute path to the component bundle on disk.
    public var bundlePath: String

    public var version: String

    /// First time this plugin was observed by the scanner.
    public var installDate: Date

    /// Updated on every scan so we can detect removed plugins.
    public var lastSeenDate: Date

    /// Soft-delete flag — set when the plugin is no longer found on disk.
    public var isRemoved: Bool

    // MARK: - GRDB

    public static let databaseTableName = "plugin"

    // MARK: - Init

    public init(
        id: String,
        name: String,
        manufacturer: String,
        type: String,
        subtype: Int,
        bundlePath: String,
        version: String,
        installDate: Date,
        lastSeenDate: Date,
        isRemoved: Bool = false
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.type = type
        self.subtype = subtype
        self.bundlePath = bundlePath
        self.version = version
        self.installDate = installDate
        self.lastSeenDate = lastSeenDate
        self.isRemoved = isRemoved
    }

    // MARK: - Helpers

    /// Convenience accessor that maps the raw `type` string to the typed enum.
    public var pluginType: PluginType? { PluginType(rawValue: type) }
}
