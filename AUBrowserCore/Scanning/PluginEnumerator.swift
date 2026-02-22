// AUBrowserCore/Scanning/PluginEnumerator.swift

import AudioToolbox
import AVFoundation
import Foundation

/// Enumerates every valid, installed Audio Unit component on the system.
///
/// Two sources are cross-referenced:
/// 1. `AVAudioUnitComponentManager` — provides full metadata (name, manufacturer, type, version).
/// 2. `~/Library/Preferences/com.apple.audiounits.cache` — Apple's auval validation cache.
///    Only components that appear here (and are marked valid) enter the scan queue.
///    If the cache is unreadable, all components from the manager are accepted.
public enum PluginEnumerator {

    // MARK: - Public API

    /// Returns a `Plugin` value for every installed AU that has passed auval validation.
    ///
    /// - Parameter existingPlugins: Plugins already stored in the DB. Used to preserve
    ///   the original `installDate` for components we have seen before.
    /// - Returns: Plugins sorted by name, with `isRemoved = false` and `lastSeenDate = now`.
    public static func enumerateInstalledPlugins(
        existingPlugins: [Plugin] = []
    ) async -> [Plugin] {

        // Build a lookup so we can restore installDate for known plugins
        let existingById = Dictionary(
            existingPlugins.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Run all synchronous AU enumeration off the main thread so the UI
        // stays responsive during what can be a multi-second system call.
        return await Task.detached(priority: .userInitiated) {
            let validatedKeys = parseAUValCache()

            var wildcard = AudioComponentDescription(
                componentType:         UInt32(0),
                componentSubType:      UInt32(0),
                componentManufacturer: UInt32(0),
                componentFlags:        UInt32(0),
                componentFlagsMask:    UInt32(0)
            )
            let components = AVAudioUnitComponentManager.shared()
                .components(matching: wildcard)

            let now = Date()
            var seen    = Set<String>()
            var plugins: [Plugin] = []

            // Apple's manufacturer OSType code ('appl')
            let appleManufacturer: OSType = 0x6170706C

            for component in components {
                let desc = component.audioComponentDescription

                // Skip Apple built-in AUs — they ship with every DAW and
                // add noise without value for a third-party plugin browser.
                if desc.componentManufacturer == appleManufacturer { continue }

                // Skip non-audio-processing types (view components, mixers,
                // output units, format converters, etc.)
                guard let pluginType = mapType(desc.componentType) else { continue }

                let key = ComponentKey(desc)
                if let validatedKeys, !validatedKeys.contains(key) { continue }

                let pluginId = makeID(for: component)
                guard seen.insert(pluginId).inserted else { continue }

                let existing = existingById[pluginId]

                plugins.append(Plugin(
                    id:           pluginId,
                    name:         component.name,
                    manufacturer: component.manufacturerName,
                    type:         pluginType.rawValue,
                    subtype:      Int(desc.componentSubType),
                    bundlePath:   component.componentURL?.path ?? "",
                    version:      formatVersion(component.version),
                    installDate:  existing?.installDate ?? now,
                    lastSeenDate: now,
                    isRemoved:    false
                ))
            }

            return plugins.sorted {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
        }.value
    }

    // MARK: - Private: ComponentKey

    /// Lightweight hashable identity for cross-referencing the two data sources.
    private struct ComponentKey: Hashable {
        let type:         UInt32
        let subtype:      UInt32
        let manufacturer: UInt32

        init(_ desc: AudioComponentDescription) {
            type         = desc.componentType
            subtype      = desc.componentSubType
            manufacturer = desc.componentManufacturer
        }
    }

    // MARK: - Private: auval cache parsing

    private static let auvalCacheURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Preferences/com.apple.audiounits.cache"
        )

    /// Reads `com.apple.audiounits.cache` and returns the set of
    /// validated component descriptions. Returns `nil` when the cache is
    /// missing, unreadable, or yields no results (triggering the fallback).
    private static func parseAUValCache() -> Set<ComponentKey>? {
        guard
            let data = try? Data(contentsOf: auvalCacheURL),
            let raw  = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ),
            let root = raw as? [String: Any]
        else { return nil }

        var result = Set<ComponentKey>()
        walkDict(root, into: &result)
        return result.isEmpty ? nil : result
    }

    /// Recursively walks a plist dictionary looking for component descriptor
    /// dicts that contain `type` / `subt` / `manu` integer keys.
    ///
    /// The cache format is undocumented and has varied across macOS versions.
    /// Walking the full tree makes the parser resilient to layout changes.
    private static func walkDict(
        _ dict: [String: Any],
        into result: inout Set<ComponentKey>
    ) {
        // A component descriptor contains at least these three integer keys.
        // The optional "v" key marks validity: 1 = valid, 0 = invalid, absent = valid.
        if let typeInt = dict["type"] as? Int,
           let subtInt = dict["subt"] as? Int,
           let manuInt = dict["manu"] as? Int {

            let valid = (dict["v"] as? Int) ?? 1
            if valid != 0 {
                result.insert(ComponentKey(AudioComponentDescription(
                    componentType:         UInt32(truncatingIfNeeded: typeInt),
                    componentSubType:      UInt32(truncatingIfNeeded: subtInt),
                    componentManufacturer: UInt32(truncatingIfNeeded: manuInt),
                    componentFlags:        UInt32(0),
                    componentFlagsMask:    UInt32(0)
                )))
            }
            // Don't recurse further once we've matched a descriptor.
            return
        }

        for value in dict.values {
            switch value {
            case let nested as [String: Any]:
                walkDict(nested, into: &result)
            case let array as [Any]:
                for element in array {
                    if let d = element as? [String: Any] {
                        walkDict(d, into: &result)
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - Internal: component index (used by ScanQueueManager)

    /// Builds a one-time index of every installed component's `AudioComponentDescription`,
    /// keyed by the same plugin ID used in the database.
    ///
    /// `ScanQueueManager` calls this once per scan session so it can pass the correct
    /// type / subtype / manufacturer codes to `CaptureHelper` without storing them in the DB.
    static func buildComponentIndex() -> [String: AudioComponentDescription] {
        var wildcard = AudioComponentDescription(
            componentType:         UInt32(0),
            componentSubType:      UInt32(0),
            componentManufacturer: UInt32(0),
            componentFlags:        UInt32(0),
            componentFlagsMask:    UInt32(0)
        )
        let components = AVAudioUnitComponentManager.shared()
            .components(matching: wildcard)

        let appleManufacturer: OSType = 0x6170706C
        var index: [String: AudioComponentDescription] = [:]
        for component in components {
            let desc = component.audioComponentDescription
            guard desc.componentManufacturer != appleManufacturer,
                  mapType(desc.componentType) != nil
            else { continue }
            index[makeID(for: component)] = desc
        }
        return index
    }

    // MARK: - Private: helpers

    /// Stable plugin ID: `<bundleID>_<subtypeHex>`
    ///
    /// Using the bundle identifier keeps the ID stable across version updates.
    /// The subtype hex disambiguates multiple components inside one bundle
    /// (e.g. a manufacturer that ships both an instrument and an effect).
    private static func makeID(for component: AVAudioUnitComponent) -> String {
        let bundleId = component.componentURL
            .flatMap { url -> String? in
                guard url.isFileURL else { return nil }
                return Bundle(url: url)?.bundleIdentifier
            }
            ?? "\(component.manufacturerName).\(component.name)"
                .replacingOccurrences(of: " ", with: "_")
        let subtype = component.audioComponentDescription.componentSubType
        let hex = String(subtype, radix: 16, uppercase: false)
        let paddedHex = String(repeating: "0", count: max(0, 8 - hex.count)) + hex
        return "\(bundleId)_\(paddedHex)"
    }

    /// Maps an AU `componentType` OSType to a `PluginType`.
    /// Returns `nil` for types that are not audio-processing units
    /// (mixers, output units, format converters, view components, etc.)
    /// so callers can skip them entirely.
    private static func mapType(_ type: OSType) -> PluginType? {
        switch type {
        case kAudioUnitType_MusicDevice:                 return .instrument
        case kAudioUnitType_Effect, kAudioUnitType_MusicEffect: return .effect
        case kAudioUnitType_MIDIProcessor:               return .midi
        case kAudioUnitType_Generator:                   return .generator
        default:                                         return nil
        }
    }

    /// Decodes a packed AU version UInt32 → `"major.minor.patch"`.
    ///
    ///  Bits 31–24: major  |  Bits 23–16: minor  |  Bits 15–0: patch
    private static func formatVersion<T: BinaryInteger>(_ version: T) -> String {
        let v     = UInt32(truncatingIfNeeded: version)
        let major = (v >> 24) & 0xFF
        let minor = (v >> 16) & 0xFF
        let patch =  v        & 0xFFFF
        return "\(major).\(minor).\(patch)"
    }
}
