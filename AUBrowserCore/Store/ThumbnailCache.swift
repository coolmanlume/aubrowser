// AUBrowserCore/Store/ThumbnailCache.swift

import AppKit
import Foundation

/// An in-memory JPEG thumbnail cache backed by `NSCache`.
///
/// `NSCache` automatically evicts entries under memory pressure and is
/// thread-safe, so `ThumbnailCache` can be called from any context.
///
/// Loading from disk is dispatched to a background priority task so it never
/// blocks the main thread.  Concurrent requests for the same `pluginId` are
/// coalesced — only one disk read happens regardless of how many callers race.
public final class ThumbnailCache: @unchecked Sendable {

    // MARK: - Private state

    private let cache = NSCache<NSString, NSImage>()

    /// In-flight load tasks, keyed by the JPEG file path.
    /// Prevents duplicate disk reads when the grid scrolls quickly.
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let lock = NSLock()

    // MARK: - Shared

    /// App-wide singleton. Views reference this directly.
    public static let shared = ThumbnailCache()

    // MARK: - Init

    /// - Parameter countLimit: Maximum number of images to keep in memory.
    ///   Set to 0 for no limit (NSCache manages automatically by cost).
    public init(countLimit: Int = 300) {
        cache.countLimit = countLimit
    }

    // MARK: - Public API

    /// Returns the cached image if available, otherwise loads it from disk
    /// and stores it before returning.  Returns `nil` if the file is missing
    /// or unreadable.
    public func image(for thumbnail: Thumbnail) async -> NSImage? {
        let key = thumbnail.jpegPath as NSString

        // Fast path — already in memory
        if let hit = cache.object(forKey: key) { return hit }

        // Coalesce concurrent requests for the same path
        lock.lock()
        if let existing = inFlight[thumbnail.jpegPath] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<NSImage?, Never>(priority: .utility) { [weak self] in
            guard let self else { return nil }
            let image = NSImage(contentsOfFile: thumbnail.jpegPath)
            if let image {
                self.cache.setObject(image, forKey: key)
            }
            self.lock.lock()
            self.inFlight.removeValue(forKey: thumbnail.jpegPath)
            self.lock.unlock()
            return image
        }

        inFlight[thumbnail.jpegPath] = task
        lock.unlock()

        return await task.value
    }

    /// Removes the cached image for a specific JPEG path.
    /// Call this after a successful rescan so the gallery shows the new capture.
    public func invalidate(jpegPath: String) {
        cache.removeObject(forKey: jpegPath as NSString)
    }

    /// Removes all cached images.  Called before a full rescan.
    public func removeAll() {
        cache.removeAllObjects()
    }
}
