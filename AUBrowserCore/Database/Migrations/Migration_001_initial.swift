// AUBrowserCore/Database/Migrations/Migration_001_initial.swift

import GRDB

/// Creates the initial four-table schema.
///
/// Note: `thumbnail` is created here WITHOUT the `captureVersion` column —
/// that is added in `Migration_002_captureVersion`.
enum Migration001Initial {

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in

            // ------------------------------------------------------------------
            // plugin
            // ------------------------------------------------------------------
            try db.create(table: "plugin") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("manufacturer", .text).notNull()
                t.column("type", .text).notNull()
                t.column("subtype", .integer).notNull()
                t.column("bundlePath", .text).notNull()
                t.column("version", .text).notNull()
                t.column("installDate", .datetime).notNull()
                t.column("lastSeenDate", .datetime).notNull()
                t.column("isRemoved", .boolean).notNull().defaults(to: false)
            }

            // Indexes used by sidebar filters and incremental scan diff
            try db.create(
                index: "idx_plugin_manufacturer",
                on: "plugin", columns: ["manufacturer"]
            )
            try db.create(
                index: "idx_plugin_type",
                on: "plugin", columns: ["type"]
            )
            try db.create(
                index: "idx_plugin_isRemoved",
                on: "plugin", columns: ["isRemoved"]
            )

            // ------------------------------------------------------------------
            // thumbnail  (captureVersion added in migration 002)
            // ------------------------------------------------------------------
            try db.create(table: "thumbnail") { t in
                t.primaryKey("pluginId", .text)
                    .references("plugin", onDelete: .cascade)
                t.column("jpegPath", .text).notNull()
                t.column("widthPx", .integer).notNull()
                t.column("heightPx", .integer).notNull()
                t.column("capturedAt", .datetime).notNull()
            }

            // ------------------------------------------------------------------
            // scanRecord  (append-only log; id is the SQLite rowid alias)
            // ------------------------------------------------------------------
            try db.create(table: "scanRecord") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pluginId", .text).notNull()
                    .references("plugin", onDelete: .cascade)
                t.column("attemptedAt", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("failureReason", .text)
                t.column("durationSeconds", .double).notNull()
            }

            try db.create(
                index: "idx_scanRecord_pluginId",
                on: "scanRecord", columns: ["pluginId"]
            )

            // ------------------------------------------------------------------
            // userData
            // ------------------------------------------------------------------
            try db.create(table: "userData") { t in
                t.primaryKey("pluginId", .text)
                    .references("plugin", onDelete: .cascade)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("notes", .text)
                t.column("userSortIndex", .integer)
            }

            try db.create(
                index: "idx_userData_isFavorite",
                on: "userData", columns: ["isFavorite"]
            )
        }
    }
}
