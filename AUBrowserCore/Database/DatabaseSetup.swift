// AUBrowserCore/Database/DatabaseSetup.swift

import Foundation
import GRDB

/// Single entry point for all database access in AUBrowserCore.
///
/// Owns the `DatabasePool` (WAL mode, concurrent reads) and runs all
/// migrations on first launch. Expose `DatabaseSetup.shared` to the rest
/// of the app; inject `dbPool` into `PluginStore` and `ScanQueueManager`.
public final class DatabaseSetup {

    // MARK: - Capture version

    /// Bump this constant to force every plugin to be re-captured on next launch.
    /// ScanQueueManager compares this against `Thumbnail.captureVersion` and
    /// re-queues any plugin whose stored value is lower.
    public static let currentCaptureVersion: Int = 1

    // MARK: - Singleton

    public static let shared: DatabaseSetup = {
        do {
            return try DatabaseSetup()
        } catch {
            fatalError("AUBrowser: failed to open database — \(error)")
        }
    }()

    // MARK: - Public properties

    /// WAL-mode pool: many concurrent readers, one serialised writer.
    public let dbPool: DatabasePool

    /// `~/Library/Application Support/AUBrowser/thumbnails/`
    public let thumbnailsDirectory: URL

    // MARK: - Init

    public init() throws {
        // Resolve ~/Library/Application Support/AUBrowser/
        let appSupport = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("AUBrowser", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        // Thumbnails sub-directory
        thumbnailsDirectory = appSupport
            .appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(
            at: thumbnailsDirectory,
            withIntermediateDirectories: true
        )

        // Open database (DatabasePool enables WAL automatically)
        var config = Configuration()
        config.prepareDatabase { db in
            // Enforce FK constraints on every connection opened by the pool
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbURL = appSupport.appendingPathComponent("AUBrowser.db")
        dbPool = try DatabasePool(path: dbURL.path, configuration: config)

        try applyMigrations()
    }

    // MARK: - Helpers

    /// Fetches all plugin rows from the database. Used by the app target during
    /// startup so that ContentView doesn't need to import GRDB directly.
    public func fetchAllPlugins() async -> [Plugin] {
        (try? await dbPool.read { db in try Plugin.fetchAll(db) }) ?? []
    }

    /// Returns the canonical JPEG path for a given plugin id + version string.
    /// Format: `{thumbnailsDirectory}/{pluginId}_{versionHash}.jpg`
    public func jpegURL(pluginId: String, version: String) -> URL {
        let hash = version
            .data(using: .utf8)
            .map { String(abs($0.hashValue), radix: 16) } ?? version
        let filename = "\(pluginId)_\(hash).jpg"
            .replacingOccurrences(of: "/", with: "_")
        return thumbnailsDirectory.appendingPathComponent(filename)
    }

    // MARK: - Private

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()
        Migration001Initial.register(in: &migrator)
        Migration002CaptureVersion.register(in: &migrator)
        try migrator.migrate(dbPool)
    }
}
