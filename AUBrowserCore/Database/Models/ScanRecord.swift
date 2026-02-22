// AUBrowserCore/Database/Models/ScanRecord.swift

import Foundation
import GRDB

// MARK: - Supporting enums

public enum ScanStatus: String, Codable, CaseIterable {
    case success
    case timeout
    case failed
    case skipped
}

public enum ScanFailureReason: String, Codable, CaseIterable {
    case licenseDialog = "license_dialog"
    case crash
    case hang
    case noView       = "no_view"
    case bitmapFailed = "bitmap_failed"
    case jpegFailed   = "jpeg_failed"
    case writeFailed  = "write_failed"
}

// MARK: - ScanRecord

/// Written immediately when a CaptureHelper subprocess finishes (or is killed).
/// One record per capture attempt — multiple rows per plugin are valid.
public struct ScanRecord: Codable, FetchableRecord, PersistableRecord {

    // MARK: - Stored properties

    /// Auto-assigned by SQLite on insert. nil before first insertion.
    public var id: Int64?

    /// FK → Plugin.id
    public var pluginId: String

    public var attemptedAt: Date

    /// Raw string mapped from `ScanStatus`.
    public var status: String

    /// Raw string mapped from `ScanFailureReason`; nil on success.
    public var failureReason: String?

    /// Wall-clock seconds the CaptureHelper process was alive.
    public var durationSeconds: Double

    // MARK: - GRDB

    public static let databaseTableName = "scanRecord"

    // MARK: - Init

    public init(
        pluginId: String,
        attemptedAt: Date = Date(),
        status: ScanStatus,
        failureReason: ScanFailureReason? = nil,
        durationSeconds: Double
    ) {
        self.id = nil
        self.pluginId = pluginId
        self.attemptedAt = attemptedAt
        self.status = status.rawValue
        self.failureReason = failureReason?.rawValue
        self.durationSeconds = durationSeconds
    }

    // MARK: - GRDB insert hook

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Typed accessors

    public var scanStatus: ScanStatus? { ScanStatus(rawValue: status) }

    public var scanFailureReason: ScanFailureReason? {
        failureReason.flatMap { ScanFailureReason(rawValue: $0) }
    }
}
