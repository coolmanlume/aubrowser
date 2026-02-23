# AUBrowser — Project Planning Document

## Overview

A native macOS app that browses all installed Audio Unit (AU) plugins with auto-captured JPEG thumbnails of each plugin's GUI, progressive scanning with timeout handling, and rich filtering/sorting by name, manufacturer, type, install date, and user tags.

---

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI + AppKit bridges (NSCollectionView, NSTableView)
- **Database:** SQLite via GRDB
- **Concurrency:** Swift async/await + AsyncSemaphore
- **External dependencies:** GRDB 6.0+, swift-async-algorithms 1.0+
- **macOS target:** 14.0+
- **Sandbox:** DISABLED (required for AU instantiation)

---

## Architecture — 3 Xcode Targets

### 1. AUBrowser (main app)
- SwiftUI entry point
- Views only — no business logic
- Embeds CaptureHelper binary in `Contents/Helpers/`

### 2. AUBrowserCore (shared framework)
- GRDB schema and migrations
- Data models
- ScanQueueManager
- PluginStore (query layer)
- PluginEnumerator

### 3. CaptureHelper (command line executable)
- Spawned as a subprocess per plugin capture
- Instantiates AU, renders GUI offscreen, writes JPEG, exits
- Isolated from main app — crashes and hangs are contained

---

## Project File Structure

```
AUBrowser.xcodeproj
├── AUBrowser/
│   ├── App/
│   │   ├── AUBrowserApp.swift
│   │   └── AUBrowserCommands.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── Sidebar/
│   │   │   ├── SidebarView.swift
│   │   │   └── FilterRow.swift
│   │   ├── Toolbar/
│   │   │   ├── ToolbarSearchBar.swift
│   │   │   └── ScanProgressBanner.swift
│   │   ├── Gallery/
│   │   │   ├── PluginGalleryView.swift
│   │   │   ├── PluginGridView.swift
│   │   │   ├── PluginCardItem.swift
│   │   │   ├── PluginListView.swift
│   │   │   └── PluginDetailPopover.swift
│   │   └── Shared/
│   │       ├── SkeletonCardView.swift
│   │       └── PlaceholderThumbnail.swift
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── AUBrowser.entitlements
│
├── AUBrowserCore/
│   ├── Database/
│   │   ├── DatabaseSetup.swift
│   │   ├── Models/
│   │   │   ├── Plugin.swift
│   │   │   ├── Thumbnail.swift
│   │   │   ├── ScanRecord.swift
│   │   │   └── UserData.swift
│   │   └── Migrations/
│   │       ├── Migration_001_initial.swift
│   │       └── Migration_002_captureVersion.swift
│   ├── Scanning/
│   │   ├── ScanQueueManager.swift
│   │   ├── PluginEnumerator.swift
│   │   └── AsyncSemaphore.swift
│   ├── Store/
│   │   ├── PluginStore.swift
│   │   └── ThumbnailCache.swift
│   └── Types/
│       ├── SortOrder.swift
│       ├── ViewMode.swift
│       └── PluginFilter.swift
│
└── CaptureHelper/
    ├── main.swift
    └── OffscreenRenderer.swift
```

---

## Database Schema (GRDB + SQLite)

### Plugin
```swift
struct Plugin: Codable, FetchableRecord, PersistableRecord {
    var id: String                // bundle ID + component subtype hash
    var name: String
    var manufacturer: String
    var type: String              // instrument, effect, midi, generator
    var subtype: Int              // AU four-char code
    var bundlePath: String
    var version: String
    var installDate: Date
    var lastSeenDate: Date
    var isRemoved: Bool           // soft delete
}
```

### Thumbnail
```swift
struct Thumbnail: Codable, FetchableRecord, PersistableRecord {
    var pluginId: String          // FK → Plugin.id
    var jpegPath: String
    var widthPx: Int
    var heightPx: Int
    var capturedAt: Date
    var captureVersion: Int       // bump to force global re-render
}
```

### ScanRecord
```swift
struct ScanRecord: Codable, FetchableRecord, PersistableRecord {
    var pluginId: String
    var attemptedAt: Date
    var status: String            // success, timeout, failed, skipped
    var failureReason: String?    // "license_dialog", "crash", "hang"
    var durationSeconds: Double
}
```

### UserData
```swift
struct UserData: Codable, FetchableRecord, PersistableRecord {
    var pluginId: String
    var isFavorite: Bool
    var tags: String              // comma-separated
    var notes: String?
    var userSortIndex: Int?
}
```

---

## Thumbnail Spec

- **Format:** JPEG at 50% quality
- **Width:** 680px fixed, height scaled proportionally (capped at 680px)
- **Storage:** `~/Library/Application Support/AUBrowser/thumbnails/`
- **Naming:** `{bundleID}_{versionHash}.jpg`
- **Estimated size:** 30–50KB per thumbnail (~25MB for 500 plugins)

---

## Plugin Source of Truth

Rather than blindly enumerating all AU components, cross-reference two sources:

1. **`~/Library/Preferences/com.apple.audiounits.cache`** — Apple's AU validation cache. Parse this binary plist to get the list of plugins that have passed `auval` validation (i.e. Logic-approved plugins only).
2. **`AVAudioUnitComponentManager`** — cross-reference for full metadata (name, manufacturer, type, version).

This eliminates broken/untested plugins from the scan queue before any capture attempt.

---

## Scan Queue Manager

### Key behaviours
- Diffs installed plugins against DB on every launch
- Only queues plugins with no thumbnail or outdated `captureVersion`
- Processes 3 plugins in parallel (configurable)
- Hard timeout of 20 seconds per plugin capture process
- Writes ScanRecord immediately on completion or failure
- Writes Thumbnail only on success
- On timeout or crash: logs failure reason, shows placeholder card in UI
- DB writes are immediate (not batched) — scan survives app quit mid-run

### Scan states per plugin
`instantiating` → `rendering_gui` → `capturing` → `success | timeout | failed`

### Incremental scan
Subsequent launches only process:
- New plugins not yet in DB
- Plugins whose version has changed
- Plugins explicitly flagged for re-render by user

### Force re-render
- Per plugin: right-click context menu → "Rescan"
- Global: Settings → "Rescan All" (with confirmation)

---

## CaptureHelper — Full Implementation

```swift
// CaptureHelper/main.swift
// Called as: CaptureHelper <type> <subtype> <manufacturer> <outputPath> <maxWidth>

import Foundation
import AudioToolbox
import AVFoundation
import AppKit
import CoreAudioKit

guard CommandLine.arguments.count == 6 else { fputs("Invalid arguments\n", stderr); exit(1) }

let typeCode         = UInt32(CommandLine.arguments[1])!
let subTypeCode      = UInt32(CommandLine.arguments[2])!
let manufacturerCode = UInt32(CommandLine.arguments[3])!
let outputPath       = CommandLine.arguments[4]
let maxWidth         = Int(CommandLine.arguments[5])!

var desc = AudioComponentDescription(
    componentType: typeCode,
    componentSubType: subTypeCode,
    componentManufacturer: manufacturerCode,
    componentFlags: 0,
    componentFlagsMask: 0
)

guard let component = AudioComponentFindNext(nil, &desc) else {
    fputs("Component not found\n", stderr); exit(2)
}

let semaphore = DispatchSemaphore(value: 0)
var audioUnit: AVAudioUnit?

AVAudioUnit.instantiate(with: desc, options: .loadOutOfProcess) { au, error in
    audioUnit = au
    semaphore.signal()
}

if semaphore.wait(timeout: .now() + 10) == .timedOut {
    fputs("TIMEOUT:instantiation\n", stderr); exit(3)
}

guard let au = audioUnit else { fputs("FAILED:instantiation\n", stderr); exit(4) }

var viewController: NSViewController?
let viewSemaphore = DispatchSemaphore(value: 0)

au.auAudioUnit.requestViewController { vc in
    viewController = vc
    viewSemaphore.signal()
}

if viewSemaphore.wait(timeout: .now() + 8) == .timedOut {
    fputs("TIMEOUT:gui_render\n", stderr); exit(5)
}

guard let vc = viewController, let pluginView = vc.view as? NSView else {
    fputs("FAILED:no_view\n", stderr); exit(6)
}

pluginView.layoutSubtreeIfNeeded()

let originalSize = pluginView.bounds.size
let scale = min(CGFloat(maxWidth) / originalSize.width, 1.0)
let targetSize = CGSize(
    width: round(originalSize.width * scale),
    height: min(round(originalSize.height * scale), CGFloat(maxWidth))
)

let offscreenWindow = NSWindow(
    contentRect: NSRect(origin: .zero, size: originalSize),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
offscreenWindow.isReleasedWhenClosed = false
offscreenWindow.contentView = pluginView

RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))

guard let bitmapRep = pluginView.bitmapImageRepForCachingDisplay(in: pluginView.bounds) else {
    fputs("FAILED:bitmap\n", stderr); exit(7)
}
pluginView.cacheDisplay(in: pluginView.bounds, to: bitmapRep)

let finalImage = NSImage(size: targetSize)
finalImage.lockFocus()
bitmapRep.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: originalSize),
               operation: .copy, fraction: 1.0,
               respectFlipped: true,
               hints: [.interpolation: NSImageInterpolation.high.rawValue])
finalImage.unlockFocus()

guard
    let tiffData = finalImage.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5])
else { fputs("FAILED:jpeg_encoding\n", stderr); exit(8) }

do {
    try jpegData.write(to: URL(fileURLWithPath: outputPath))
    print("\(Int(targetSize.width))x\(Int(targetSize.height))")
    exit(0)
} catch {
    fputs("FAILED:write:\(error)\n", stderr); exit(9)
}
```

### Exit codes
| Code | Meaning |
|------|---------|
| 0 | Success — JPEG written, dimensions printed to stdout |
| 1 | Invalid arguments |
| 2 | Component not found |
| 3 | TIMEOUT: instantiation (>10s) |
| 4 | FAILED: instantiation |
| 5 | TIMEOUT: GUI render (>8s) |
| 6 | FAILED: no view returned |
| 7 | FAILED: bitmap capture |
| 8 | FAILED: JPEG encoding |
| 9 | FAILED: disk write |

---

## Main App — Spawning CaptureHelper

```swift
let process = Process()
process.executableURL = helperURL
process.arguments = [typeCode, subType, manufacturer, outputPath, "680"]

let stderr = Pipe()
let stdout = Pipe()
process.standardError = stderr
process.standardOutput = stdout

process.launch()

DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
    if process.isRunning {
        process.terminate()
        // log as timeout in ScanRecord
    }
}
```

---

## UI Structure

### Layout
`NavigationSplitView` with a narrow sidebar (180–220px) and a main detail area.

### Toolbar (top)
- Search field (center, always visible, real-time filtering)
- Sort picker: Name / Manufacturer / Type / Date / Favorites
- View toggle: Grid | List (segmented control)
- Scan progress indicator (far right, animated during scan)

### Sidebar (left)
- **Type:** All / Instruments / Effects / MIDI / Generators
- **Manufacturer:** auto-populated list
- **Tags:** Favorites + user custom tags
- Multi-select with Command-click
- "Clear all filters" pill when any filter active

### Main area — Grid view
- `NSCollectionView` wrapped in `NSViewRepresentable`
- ~220px wide cards, adaptive columns filling window width
- Each card: JPEG thumbnail + plugin name + manufacturer label
- Hover: overlay with Favorite / Force Rescan / Copy Name actions
- Failed captures: clean placeholder (waveform silhouette icon)
- Skeleton loader cards during progressive scan

### Main area — List view
- `NSTableView` wrapped in `NSViewRepresentable`
- Columns: Thumbnail (52px) / Name / Manufacturer / Type / Version / Install Date
- Sortable by clicking any column header
- Columns reorderable and resizable
- Row height: 48px

### Detail popover
- Triggered by clicking any card or row
- Shows full-size thumbnail + all metadata
- Favorite toggle, tag editor, notes field, manual rescan button

### Search behaviour
- 80ms debounce on keystroke
- Fuzzy match across name, manufacturer, type simultaneously
- Compounds with active sidebar filters
- All filtering via GRDB SQL queries against local DB — feels instant

---

## Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

---

## Build Phase Script (copy helper into app bundle)

```bash
cp "${BUILT_PRODUCTS_DIR}/CaptureHelper" \
   "${BUILT_PRODUCTS_DIR}/AUBrowser.app/Contents/Helpers/CaptureHelper"
chmod +x \
   "${BUILT_PRODUCTS_DIR}/AUBrowser.app/Contents/Helpers/CaptureHelper"
```

Build scheme order: CaptureHelper → AUBrowserCore → AUBrowser

---

## SPM Dependencies

```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0")
]
```

---

## Implementation Order for Claude Code

Start in this sequence to avoid dependency issues:

1. **AUBrowserCore — Types** (SortOrder, ViewMode, PluginFilter enums)
2. **AUBrowserCore — Models** (Plugin, Thumbnail, ScanRecord, UserData)
3. **AUBrowserCore — DatabaseSetup** (GRDB migrator + schema)
4. **CaptureHelper — main.swift** (full implementation above)
5. **AUBrowserCore — PluginEnumerator** (AVAudioUnitComponentManager + auval cache parsing)
6. **AUBrowserCore — ScanQueueManager** (queue, concurrency, subprocess spawning)
7. **AUBrowserCore — PluginStore** (query layer, debounced search, filters)
8. **AUBrowser — Views** (ContentView → Sidebar → Toolbar → Gallery → Grid/List)

---

*Generated from planning session — Claude.ai*
