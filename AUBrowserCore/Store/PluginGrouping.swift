// AUBrowserCore/Store/PluginGrouping.swift

import Foundation

/// A single component variant within a `PluginGroup` — e.g. the mono, stereo,
/// or "Live" registration of the same underlying plugin.
public struct PluginVariant: Identifiable, Equatable {
    public var row: PluginRow

    /// Human-readable description of what distinguishes this variant from its
    /// siblings, e.g. "Stereo", "Mono → Stereo", "Live · Mono". `nil` when the
    /// plugin name carried no recognisable channel/Live marker (a lone variant).
    public var label: String?

    public var id: String { row.id }
}

/// Several AU component registrations that represent the same underlying plugin —
/// typically mono/stereo (and sometimes up-mix or "Live") variants that manufacturers
/// like Waves ship as separate components sharing one bundle.
///
/// The gallery shows one card per `PluginGroup`; the full variant list is surfaced
/// in the detail panel rather than as separate cards.
public struct PluginGroup: Identifiable, Equatable {
    /// Stable identity — the representative (`primary`) variant's plugin id.
    public var id: String

    /// Clean product name with channel/Live markers stripped, e.g. "Bass Rider".
    public var displayName: String

    public var manufacturer: String

    /// The variant used for the card thumbnail and headline metadata —
    /// preferring whichever variant already has a captured thumbnail.
    public var primary: PluginRow

    /// Every variant in the group, including `primary`, sorted for display.
    public var variants: [PluginVariant]

    public var hasMultipleVariants: Bool { variants.count > 1 }

    /// All underlying `Plugin` values — used to fan out batch actions like rescan.
    public var plugins: [Plugin] { variants.map(\.row.plugin) }
}

/// Groups a flat list of `PluginRow`s into `PluginGroup`s, folding mono/stereo/
/// up-mix component variants — and, when a non-"Live" sibling exists, "Live"
/// variants — into a single entry per underlying plugin.
public enum PluginGrouping {

    public static func group(_ rows: [PluginRow]) -> [PluginGroup] {
        // MARK: Pass 1 — group by (channel-suffix-stripped name, manufacturer, bundlePath)

        struct Key: Hashable {
            let base: String
            let manufacturer: String
            let bundlePath: String
        }

        var order: [Key] = []
        var buckets: [Key: [PluginRow]] = [:]

        for row in rows {
            let (base, _) = stripChannelSuffix(row.plugin.name) ?? (row.plugin.name, nil)
            let key = Key(base: base, manufacturer: row.plugin.manufacturer, bundlePath: row.plugin.bundlePath)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]!.append(row)
        }

        // MARK: Pass 2 — fold "Live" buckets into their non-"Live" sibling, when one exists

        var liveFoldedInto: [Key: Key] = [:]
        for key in order {
            guard let strippedBase = stripLiveSuffix(key.base) else { continue }
            let siblingKey = Key(base: strippedBase, manufacturer: key.manufacturer, bundlePath: key.bundlePath)
            guard buckets[siblingKey] != nil else { continue }
            liveFoldedInto[key] = siblingKey
        }

        for (liveKey, siblingKey) in liveFoldedInto {
            guard let liveRows = buckets.removeValue(forKey: liveKey) else { continue }
            buckets[siblingKey, default: []].append(contentsOf: liveRows)
        }

        // MARK: Pass 3 — build PluginGroup values

        var groups: [PluginGroup] = []
        for key in order where !liveFoldedInto.keys.contains(key) {
            guard let bucketRows = buckets[key], !bucketRows.isEmpty else { continue }

            let variants = bucketRows
                .map { row -> PluginVariant in
                    PluginVariant(row: row, label: variantLabel(for: row.plugin.name, displayName: key.base))
                }
                .sorted { variantSortPriority($0) < variantSortPriority($1) }

            let primary = variants.first!.row

            groups.append(PluginGroup(
                id: primary.id,
                displayName: key.base,
                manufacturer: key.manufacturer,
                primary: primary,
                variants: variants
            ))
        }

        return groups
    }

    // MARK: - Channel suffix parsing

    /// Strips a trailing channel-configuration token like `" (m)"`, `" (s)"`,
    /// `" (m->s)"`, `" (5->5)"`, or `" (7.1.4)"` from a plugin name.
    ///
    /// Returns `nil` when the name has no parenthesised suffix, or the suffix
    /// doesn't look like a channel token (so unrelated names such as
    /// `"MyPlugin (Legacy)"` are left untouched).
    static func stripChannelSuffix(_ name: String) -> (base: String, token: String)? {
        guard name.hasSuffix(")"), let openParen = name.lastIndex(of: "(") else { return nil }
        let tokenRange = name.index(after: openParen)..<name.index(before: name.endIndex)
        guard tokenRange.lowerBound < tokenRange.upperBound else { return nil }

        let token = String(name[tokenRange])
        guard isChannelToken(token) else { return nil }

        var base = String(name[..<openParen])
        while base.hasSuffix(" ") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return (base, token)
    }

    private static func isChannelToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        if token.contains("->") {
            let sides = token.components(separatedBy: "->")
            return sides.count == 2 && sides.allSatisfy(isChannelAtom)
        }
        return isChannelAtom(token)
    }

    private static func isChannelAtom(_ atom: String) -> Bool {
        if atom == "m" || atom == "s" { return true }
        guard !atom.isEmpty, atom.allSatisfy({ $0.isNumber || $0 == "." }) else { return false }
        if atom.contains(".") { return true }   // e.g. "7.1", "7.1.4"
        return atom.count <= 2                   // small channel counts, e.g. "5", "16" — not a year
    }

    /// Strips a trailing `" Live"` / `"-Live"` marker (case-insensitive).
    /// Returns `nil` when the name has no such marker.
    static func stripLiveSuffix(_ base: String) -> String? {
        for separator in [" ", "-"] {
            let suffix = "\(separator)Live"
            guard base.count > suffix.count,
                  base.lowercased().hasSuffix(suffix.lowercased())
            else { continue }
            return String(base.dropLast(suffix.count))
        }
        return nil
    }

    // MARK: - Labels

    private static func variantLabel(for fullName: String, displayName: String) -> String? {
        guard let (channelBase, token) = stripChannelSuffix(fullName) else { return nil }

        let isLive = stripLiveSuffix(channelBase) != nil && channelBase.count > displayName.count
        let channelText = formatChannelToken(token)
        return isLive ? "Live · \(channelText)" : channelText
    }

    private static func formatChannelToken(_ token: String) -> String {
        if token.contains("->") {
            let sides = token.components(separatedBy: "->").map(formatChannelAtom)
            return sides.joined(separator: " → ")
        }
        return formatChannelAtom(token)
    }

    private static func formatChannelAtom(_ atom: String) -> String {
        switch atom {
        case "m": return "Mono"
        case "s": return "Stereo"
        default:  return atom.contains(".") ? atom : "\(atom)ch"
        }
    }

    /// Lower sorts first. Prefers a captured thumbnail, then stereo-ish variants,
    /// then studio (non-Live) variants, so the "best" variant becomes `primary`.
    private static func variantSortPriority(_ variant: PluginVariant) -> (Int, Int, String) {
        let hasThumb = variant.row.thumbnail != nil ? 0 : 1
        let label = variant.label ?? ""
        let isLive = label.hasPrefix("Live")
        let tokenRank: Int
        if label.contains("Stereo") && !label.contains("→") { tokenRank = 0 }
        else if label.contains("→") { tokenRank = 1 }
        else if label.contains("Mono") { tokenRank = 2 }
        else { tokenRank = 3 }
        return (hasThumb, (isLive ? 10 : 0) + tokenRank, variant.row.plugin.name)
    }
}
