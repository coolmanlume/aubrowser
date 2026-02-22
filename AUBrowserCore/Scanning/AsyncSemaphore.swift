// AUBrowserCore/Scanning/AsyncSemaphore.swift

import Foundation

/// A counting semaphore for Swift structured concurrency.
///
/// Callers `await` on `wait()` until a permit is available, then call
/// `signal()` when done to release the permit for the next waiter.
/// Permits are granted in FIFO order.
///
/// Usage:
/// ```swift
/// let semaphore = AsyncSemaphore(value: 3)   // max 3 concurrent
///
/// await withTaskGroup(of: Void.self) { group in
///     for item in items {
///         group.addTask {
///             await semaphore.wait()
///             defer { Task { await semaphore.signal() } }
///             await process(item)
///         }
///     }
/// }
/// ```
public actor AsyncSemaphore {

    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter value: Initial permit count. Must be ≥ 0.
    public init(value: Int) {
        precondition(value >= 0, "AsyncSemaphore value must be non-negative")
        count = value
    }

    /// Acquires a permit, suspending until one is available.
    public func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    /// Releases a permit, resuming the longest-waiting caller (if any).
    public func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Current number of available permits (for diagnostics / testing).
    public var availablePermits: Int { count }
}
