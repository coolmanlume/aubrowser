// AUBrowserCore/Database/Models/Thumbnail.swift

import Foundation
import GRDB

/// Stores the location and metadata of a captured plugin GUI screenshot.
///
/// One-to-one with Plugin (pluginId is a FK → Plugin.id).
/// A plugin has no thumbnail row until its first successful capture.
public struct Thumbnail: Codable, Equatable, FetchableRecord, PersistableRecord {

    // MARK: - Stored properties

    /// FK → Plugin.id
    public var pluginId: String

    /// Absolute path to the JPEG file inside Application Support.
    public var jpegPath: String

    public var widthPx: Int
    public var heightPx: Int

    public var capturedAt: Date

    /// Bumped globally in DatabaseSetup to force all plugins to re-render
    /// on the next launch (e.g. after a renderer bug fix).
    public var captureVersion: Int

    // MARK: - GRDB

    public static let databaseTableName = "thumbnail"

    // MARK: - Init

    public init(
        pluginId: String,
        jpegPath: String,
        widthPx: Int,
        heightPx: Int,
        capturedAt: Date,
        captureVersion: Int
    ) {
        self.pluginId = pluginId
        self.jpegPath = jpegPath
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.capturedAt = capturedAt
        self.captureVersion = captureVersion
    }

    // MARK: - Helpers

    public var url: URL { URL(fileURLWithPath: jpegPath) }

    public var aspectRatio: Double {
        guard heightPx > 0 else { return 1 }
        return Double(widthPx) / Double(heightPx)
    }
}
