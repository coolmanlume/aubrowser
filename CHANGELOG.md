# Changelog

## [Unreleased]

### Added
- **Plugin variant grouping** (`AUBrowserCore/Store/PluginGrouping.swift`) — mono/stereo/up-mix AU component variants of the same plugin (and, when a non-"Live" sibling exists, its "Live" counterpart) now fold into a single gallery entry instead of one card per component. Fixes manufacturers like Waves showing the same plugin 2–6 times. The card shows the group's representative variant; the detail popover gains an "Other Versions" section listing every variant with its own per-variant rescan. `PluginStore.groupedRows` is the grouped projection of `rows`; Grid, List, and selection/detail flows all consume it.
- **README.md** and **.gitignore** — project now documents itself (overview, build steps, structure) and stops tracking Xcode user-state files.
- **Show in Finder** — right-click any plugin card (grid) or row (list) to reveal its `.component` bundle in Finder via `NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)`.
- **Multi-selection (grid)** — Cmd+click cards to build a selection. Selected cards show an accent-colour border and a `checkmark.circle.fill` badge. Plain click opens the detail sheet and clears the selection.
- **Multi-selection (list)** — native `Table` selection binding; Shift/Cmd+click rows as expected on macOS.
- **SelectionActionBar** — appears at the bottom of the gallery whenever one or more plugins are selected. Provides three batch actions:
  - *Like All* — sets `isFavorite = true` for all selected plugins in a single DB transaction (`PluginStore.addToFavorites(pluginIds:)`).
  - *Rescan Selected* — re-captures thumbnails for every variant of the selected groups (`ScanQueueManager.rescan(_ plugins:)`, expanded via `PluginStore.plugins(inGroups:)`).
  - *Deselect* — clears the selection.
- **Linear progress bar** — a thin `ProgressView(.linear)` appears between the toolbar and the gallery while a scan is running, filling from 0 → 1 as plugins complete. Complements the existing `ScanProgressBanner` counter.

### Changed
- **Incremental/full scan only captures each group's representative variant** — `ScanQueueManager.computeQueue(groupPrimariesOnly:)` folds the plugin list through `PluginGrouping` before deciding what needs a `CaptureHelper` spawn, so mono/stereo/Live duplicates are no longer captured automatically (they're never shown on their own card). Explicit rescans (single plugin, "Rescan All Versions" in the detail panel, "Rescan Selected") bypass this and always capture every variant requested.
- **Capture concurrency is now also serialized per bundle path** — several distinct Waves plugins share one `WaveShell` component; instantiating it out-of-process from more than one component at a time was triggering its native "Error connecting to archiver" / "Too many parameters in process" alert dialogs. A per-`bundlePath` semaphore (value 1) now sits alongside the existing global `maxConcurrent` cap, so only one capture against any given shared bundle runs at a time while unrelated bundles still run fully in parallel.
- **SelectionActionBar's "Rescan All" renamed to "Rescan Selected"** — it only ever acted on the current selection; the old label collided in meaning with the menu's whole-library "Rescan All Plugins…" (⌘⇧R), which remains the only way to trigger a full rescan.
- **CaptureHelper timeout** — RunLoop wait reduced from 5 s to 4 s (`Date(timeIntervalSinceNow: 4.0)`).
- **Plugin removal — hard delete** — `ScanQueueManager.markRemovedPlugins` now hard-deletes plugin rows instead of soft-deleting (`isRemoved = true`). SQLite `ON DELETE CASCADE` automatically removes the related `thumbnail`, `userData`, and `scanRecord` rows. The JPEG file is also deleted from disk.
- **`DatabaseSetup.fetchAllPlugins`** — now filters `isRemoved = false` to guard against stale soft-deleted rows left by older builds.

### Fixed
- **Cards disappearing during a targeted rescan** — the grid's progressive-reveal-during-scan filter (meant only for the initial library-wide scan) also fired for a single-card or selection rescan, briefly hiding every other not-yet-captured card in the library. `ScanQueueManager` now exposes `isBulkScan`, set only by `startIncrementalScan`/`startFullRescan`/`resumeScan`; the grid gates its filter on that instead of `isScanning` alone.
- **Ghost entries after plugin removal** — `PluginEnumerator` now checks `FileManager.fileExists(atPath:)` for every component URL before accepting it. `AVAudioUnitComponentManager` caches its registry and does not immediately reflect bundle deletions; the file-system check ensures components whose `.component` bundle is gone from disk are excluded from the installed list and therefore cleaned up on the next launch.

---

## Next steps / known limitations

- **46 plugins across 12 manufacturers consistently fail to capture a thumbnail** — confirmed via `scanRecord`/`thumbnail` history, not a regression from the grouping/scan work above (most are single-component plugins grouping never touches). Three distinct, reproducible failure modes, by manufacturer and count of affected plugins:
  - `no_view` (20) — plugin never hands back a GUI view within CaptureHelper's 8s window: Slate Digital (13), Arturia (3 — `Delay TAPE-201`, `Efx REFRACT`, `Tape MELLO-FI`), Sonnox (3), oeksound (1).
  - `crash` (20) — the `CaptureHelper` subprocess crashes outright instantiating the plugin: Boz Digital Labs (9), iZotope (8), FLUX (1), Pulsar (1), Sonnox (1).
  - `hang`/`timeout` (6) — GUI render exceeds the outer 20–30s timeout: Soundtoys (3), Kazrog (1), VSL (1), sonible (1).
  Likely cause: these plugins expect a real DAW host session (license/activation handshake, full audio session) that out-of-process `AVAudioUnit.instantiate(loadOutOfProcess)` + `requestViewController` doesn't provide — Slate Digital and iZotope in particular gate on license checks. Not yet investigated further; a longer render timeout might help the `no_view`/`hang` cases, but may be a fundamental limitation for the `crash` cases and license-gated plugins generally. The existing placeholder-icon + manual-rescan fallback is the only mitigation today.
- **List view double-click / Return** — opening the detail popover from a selected list row is stubbed (`// TODO`); needs a `primaryAction` handler on the `Table`.
- **`isRemoved` column** — now unused (hard-delete replaced soft-delete). A future migration could drop the column and its index to keep the schema clean.
- **ThumbnailCache eviction** — removed plugins are deleted from the DB and disk but their `NSImage` may linger in the in-memory `ThumbnailCache` until the app restarts. Low priority since the plugin row no longer appears in the gallery.
- **Full "Rescan All Plugins…" not yet re-verified end-to-end** since the grouping/concurrency changes — the automated incremental scan and targeted rescans were exercised live against the real plugin library, but a full library-wide rescan (the scenario most likely to stress the per-bundle WaveShell serialization) hasn't been run to completion and observed yet.

## Operational note: multiple stale build copies

Xcode (and any `xcodebuild` invocation without an explicit `-derivedDataPath`) compiles this project into `~/Library/Developer/Xcode/DerivedData/AU_Browser-<hash>/`, **outside** this repo and untracked by git — a pure build cache, not source. Building the same project from different tools/contexts can produce *multiple* such folders, each a fully separate compiled `.app` registered under the same bundle ID (`coolmanlume.AU-Browser`). macOS then resolves "AU Browser" (Dock, Spotlight, double-click) to whichever one it currently prefers, which can silently be a stale one — this caused the grouping fix to appear to "come back" intermittently during this session. There is and should only ever be **one** `AU_Browser-*` folder under DerivedData at a time; if more than one exists, delete the extras and do a clean build. If Xcode was left open while files were edited externally (e.g. by an AI coding assistant), do **Product → Clean Build Folder** (⇧⌘K) before the next Run — Xcode's incremental build system can otherwise miss the changes and silently relink stale object files.
