// AUBrowserCore/Scanning/ScanQueueManager.swift

import AudioToolbox
import Combine
import Foundation
import GRDB

// MARK: - ScanProgress

/// Snapshot of the current scan state — consumed by SwiftUI views.
public struct ScanProgress: Equatable {
    /// Total plugins queued for this session.
    public var total: Int = 0
    /// Plugins whose capture has finished (success or failure).
    public var completed: Int = 0
    /// Plugins that failed or timed out.
    public var failed: Int = 0
    /// Plugin IDs currently being captured (shown as active cards in the UI).
    public var inProgress: Set<String> = []

    public var remaining: Int { max(0, total - completed) }
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public var isIdle: Bool { total == 0 }
}

// MARK: - ScanQueueManager

/// Orchestrates the full plugin capture pipeline:
///
/// 1. **Upsert** — writes every installed plugin to the DB on launch.
/// 2. **Diff** — determines which plugins need a capture (new, stale version, or forced).
/// 3. **Queue** — processes up to `maxConcurrent` plugins in parallel.
/// 4. **Capture** — spawns `CaptureHelper` per plugin with a 20 s hard timeout.
/// 5. **Persist** — writes `Thumbnail` on success and `ScanRecord` on every outcome.
///
/// All `@Published` mutations happen on the main actor. Subprocess I/O never
/// blocks the main thread — the main actor is suspended (not blocked) while
/// waiting for each process to exit.
@MainActor
public final class ScanQueueManager: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var isScanning = false
    @Published public private(set) var progress = ScanProgress()

    /// Plugin IDs that have been processed (success or failure) in the current session.
    /// Used by the UI to progressively reveal cards as they complete.
    @Published public private(set) var processedIds: Set<String> = []

    /// True when a previous scan was started but is not currently running,
    /// meaning `resumeScan()` can pick up where it left off.
    public var canResume: Bool { !isScanning && !lastInstalledPlugins.isEmpty }

    // MARK: - Configuration

    /// Maximum number of `CaptureHelper` processes running simultaneously.
    public let maxConcurrent: Int

    // MARK: - Private

    private let db: DatabaseSetup
    private let helperURL: URL
    private var scanTask: Task<Void, Never>?

    /// Retained so `resumeScan()` can restart an incremental scan without
    /// re-enumerating all installed plugins from the caller's side.
    private var lastInstalledPlugins: [Plugin] = []

    // MARK: - Init

    public init(
        db: DatabaseSetup = .shared,
        helperURL: URL,
        maxConcurrent: Int = 3
    ) {
        self.db = db
        self.helperURL = helperURL
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public API

    /// Upserts all installed plugins then scans only those without an up-to-date thumbnail.
    /// Safe to call on every launch — exits immediately if nothing needs capturing.
    public func startIncrementalScan(installedPlugins: [Plugin]) {
        guard !isScanning else { return }
        lastInstalledPlugins = installedPlugins
        launch(plugins: installedPlugins, forceAll: false)
    }

    /// Re-captures every installed plugin, ignoring existing thumbnails.
    public func startFullRescan(installedPlugins: [Plugin]) {
        cancel()
        lastInstalledPlugins = installedPlugins
        launch(plugins: installedPlugins, forceAll: true)
    }

    /// Resumes an incremental scan using the last known plugin list.
    /// Does nothing if no previous scan was started or one is already running.
    public func resumeScan() {
        guard canResume else { return }
        launch(plugins: lastInstalledPlugins, forceAll: false)
    }

    /// Re-captures a single plugin by ID, cancelling any ongoing scan first.
    public func rescan(pluginId: String, among installedPlugins: [Plugin]) {
        guard let plugin = installedPlugins.first(where: { $0.id == pluginId }) else { return }
        cancel()
        launch(plugins: [plugin], forceAll: true, markRemoved: false)
    }

    /// Re-captures a single plugin directly (e.g. from the detail popover).
    public func rescan(_ plugin: Plugin) {
        cancel()
        launch(plugins: [plugin], forceAll: true, markRemoved: false)
    }

    /// Rescans an arbitrary set of plugins (e.g. from a multi-selection).
    public func rescan(_ plugins: [Plugin]) {
        cancel()
        launch(plugins: plugins, forceAll: true, markRemoved: false)
    }

    /// Stops the in-progress scan. Call `resumeScan()` to continue.
    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progress = .init()
    }

    // MARK: - Private: task lifecycle

    private func launch(plugins: [Plugin], forceAll: Bool, markRemoved: Bool = true) {
        isScanning = true
        progress = .init()
        processedIds = []

        scanTask = Task { [weak self] in
            guard let self else { return }
            await runScan(plugins: plugins, forceAll: forceAll, markRemoved: markRemoved)
            isScanning = false
            progress = .init()
        }
    }

    // MARK: - Private: main pipeline

    private func runScan(plugins: [Plugin], forceAll: Bool, markRemoved: Bool = true) async {
        guard !Task.isCancelled else { return }

        // 1. Upsert every installed plugin row, preserving installDate
        await upsertPlugins(plugins)

        // 2. Mark plugins no longer on disk as removed.
        //    Skipped for single-plugin rescans — we only have one ID so
        //    every other plugin would be incorrectly soft-deleted.
        if markRemoved {
            await markRemovedPlugins(installedIds: Set(plugins.map(\.id)))
        }

        // 3. Compute which plugins need a capture
        let queue = forceAll ? plugins : await computeScanQueue(from: plugins)

        guard !queue.isEmpty, !Task.isCancelled else { return }

        progress = ScanProgress(total: queue.count)

        // 4. Build one-time component index off the main thread
        let componentIndex = await Task.detached(priority: .userInitiated) {
            PluginEnumerator.buildComponentIndex()
        }.value

        // 5. Process concurrently, capped by semaphore
        let semaphore = AsyncSemaphore(value: maxConcurrent)

        await withTaskGroup(of: Void.self) { group in
            for plugin in queue {
                guard !Task.isCancelled else { break }

                group.addTask { @MainActor [weak self] in
                    guard let self else { return }

                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    guard !Task.isCancelled else { return }

                    progress.inProgress.insert(plugin.id)

                    let desc = componentIndex[plugin.id]
                    let succeeded = await capturePlugin(plugin, desc: desc)

                    progress.completed += 1
                    if !succeeded { progress.failed += 1 }
                    progress.inProgress.remove(plugin.id)
                    processedIds.insert(plugin.id)
                }
            }
        }
    }

    // MARK: - Private: DB helpers

    private func upsertPlugins(_ plugins: [Plugin]) async {
        do {
            try await db.dbPool.write { db in
                for plugin in plugins {
                    // INSERT if new (preserves installDate set by PluginEnumerator)
                    // UPDATE if existing (refreshes lastSeenDate, version, bundlePath)
                    try plugin.save(db)
                }
            }
        } catch {
            // Non-fatal; the scan can continue with stale DB state
        }
    }

    private func markRemovedPlugins(installedIds: Set<String>) async {
        do {
            try await db.dbPool.write { db in
                try Plugin
                    .filter(!installedIds.contains(Column("id")))
                    .updateAll(db, Column("isRemoved").set(to: true))
            }
        } catch {}
    }

    private func computeScanQueue(from plugins: [Plugin]) async -> [Plugin] {
        do {
            let thumbs = try await db.dbPool.read { db in
                try Thumbnail.fetchAll(db)
            }
            let thumbIndex = Dictionary(
                thumbs.map { ($0.pluginId, $0) },
                uniquingKeysWith: { a, _ in a }
            )
            return plugins.filter { plugin in
                guard let thumb = thumbIndex[plugin.id] else { return true }
                return thumb.captureVersion < DatabaseSetup.currentCaptureVersion
            }
        } catch {
            return plugins
        }
    }

    // MARK: - Private: capture one plugin

    /// Spawns `CaptureHelper` and waits for it to exit (or timeout).
    /// Writes a `ScanRecord` unconditionally and a `Thumbnail` only on success.
    /// - Returns: `true` on success, `false` on any failure/timeout.
    @discardableResult
    private func capturePlugin(
        _ plugin: Plugin,
        desc: AudioComponentDescription?
    ) async -> Bool {
        let startTime = Date()

        guard let desc else {
            // Component disappeared between enumeration and capture
            await writeScanRecord(pluginId: plugin.id, status: .skipped,
                                  reason: nil, duration: 0)
            return false
        }

        let outputURL = db.jpegURL(pluginId: plugin.id, version: plugin.version)

        let process    = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL  = helperURL
        process.arguments      = [
            String(desc.componentType),
            String(desc.componentSubType),
            String(desc.componentManufacturer),
            outputURL.path,
            "680"
        ]
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        do {
            try process.run()
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            await writeScanRecord(pluginId: plugin.id, status: .failed,
                                  reason: .crash, duration: duration)
            return false
        }

        // Suspend (not block) until the process exits or the 30 s timeout fires.
        // 30 s covers the 5 s RunLoop plus instantiation (10 s) and
        // view-request (8 s) timeouts in CaptureHelper.
        let timedOut = await waitForProcess(process, timeout: 30)
        let duration = Date().timeIntervalSince(startTime)

        if timedOut {
            process.terminate()
            await writeScanRecord(pluginId: plugin.id, status: .timeout,
                                  reason: .hang, duration: duration)
            return false
        }

        if process.terminationStatus == 0 {
            // stdout: "WIDTHxHEIGHT"
            let raw    = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: raw, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts  = output.split(separator: "x")
            let width  = Int(parts.first ?? "0") ?? 0
            let height = Int(parts.last  ?? "0") ?? 0

            let thumbnail = Thumbnail(
                pluginId:       plugin.id,
                jpegPath:       outputURL.path,
                widthPx:        width,
                heightPx:       height,
                capturedAt:     Date(),
                captureVersion: DatabaseSetup.currentCaptureVersion
            )
            do {
                try await db.dbPool.write { db in try thumbnail.save(db) }
            } catch {}

            await writeScanRecord(pluginId: plugin.id, status: .success,
                                  reason: nil, duration: duration)
            return true

        } else {
            let raw    = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: raw, encoding: .utf8) ?? ""
            let reason = inferFailureReason(exitCode: process.terminationStatus,
                                            stderr: errMsg)
            await writeScanRecord(pluginId: plugin.id, status: .failed,
                                  reason: reason, duration: duration)
            return false
        }
    }

    // MARK: - Private: process wait

    /// Awaits process termination without blocking the main thread.
    /// Uses both a termination handler and a DispatchQueue timer to ensure
    /// exactly one resume regardless of which fires first.
    ///
    /// - Returns: `true` if the timeout fired before the process exited.
    private func waitForProcess(
        _ process: Process,
        timeout: TimeInterval
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let lock    = NSLock()
            var resumed = false

            func resume(timedOut: Bool) {
                lock.lock()
                let first = !resumed
                if first { resumed = true }
                lock.unlock()
                if first { continuation.resume(returning: timedOut) }
            }

            DispatchQueue.global(qos: .utility)
                .asyncAfter(deadline: .now() + timeout) { resume(timedOut: true) }

            process.terminationHandler = { _ in resume(timedOut: false) }
        }
    }

    // MARK: - Private: scan record

    private func writeScanRecord(
        pluginId: String,
        status:   ScanStatus,
        reason:   ScanFailureReason?,
        duration: TimeInterval
    ) async {
        let record = ScanRecord(
            pluginId:        pluginId,
            status:          status,
            failureReason:   reason,
            durationSeconds: duration
        )
        do {
            try await db.dbPool.write { db in try record.insert(db) }
        } catch {}
    }

    // MARK: - Private: exit-code parsing

    /// Maps `CaptureHelper` exit codes and stderr output to a `ScanFailureReason`.
    private func inferFailureReason(exitCode: Int32, stderr: String) -> ScanFailureReason? {
        // Match against stderr tokens written by CaptureHelper
        if stderr.contains("TIMEOUT")                       { return .hang }
        if stderr.contains("license") ||
           stderr.contains("License")                       { return .licenseDialog }
        if stderr.contains("no_view")                       { return .noView }
        if stderr.contains("bitmap")                        { return .bitmapFailed }
        if stderr.contains("jpeg")                          { return .jpegFailed }
        if stderr.contains("write")                         { return .writeFailed }

        // Fall back on exit codes from CaptureHelper's contract
        switch exitCode {
        case 3, 5: return .hang
        case 6:    return .noView
        case 7:    return .bitmapFailed
        case 8:    return .jpegFailed
        case 9:    return .writeFailed
        default:   return .crash
        }
    }
}
