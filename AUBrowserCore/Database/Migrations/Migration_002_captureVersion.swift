// AUBrowserCore/Database/Migrations/Migration_002_captureVersion.swift

import GRDB

/// Adds `captureVersion` to the `thumbnail` table.
///
/// Existing rows default to 1. When `DatabaseSetup.currentCaptureVersion`
/// is bumped above 1, `ScanQueueManager` will re-queue every plugin whose
/// stored `captureVersion` is lower than the current value.
enum Migration002CaptureVersion {

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_captureVersion") { db in
            try db.alter(table: "thumbnail") { t in
                t.add(column: "captureVersion", .integer)
                    .notNull()
                    .defaults(to: 1)
            }
        }
    }
}
