# Changelog

## [Unreleased]

### Added
- **Show in Finder** — right-click any plugin card (grid) or row (list) to reveal its `.component` bundle in Finder via `NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)`.
- **Multi-selection (grid)** — Cmd+click cards to build a selection. Selected cards show an accent-colour border and a `checkmark.circle.fill` badge. Plain click opens the detail sheet and clears the selection.
- **Multi-selection (list)** — native `Table` selection binding; Shift/Cmd+click rows as expected on macOS.
- **SelectionActionBar** — appears at the bottom of the gallery whenever one or more plugins are selected. Provides three batch actions:
  - *Like All* — sets `isFavorite = true` for all selected plugins in a single DB transaction (`PluginStore.addToFavorites(pluginIds:)`).
  - *Rescan All* — re-captures thumbnails for the selected plugins only (`ScanQueueManager.rescan(_ plugins:)`).
  - *Deselect* — clears the selection.
- **Linear progress bar** — a thin `ProgressView(.linear)` appears between the toolbar and the gallery while a scan is running, filling from 0 → 1 as plugins complete. Complements the existing `ScanProgressBanner` counter.

### Changed
- **CaptureHelper timeout** — RunLoop wait reduced from 5 s to 4 s (`Date(timeIntervalSinceNow: 4.0)`).
- **Plugin removal — hard delete** — `ScanQueueManager.markRemovedPlugins` now hard-deletes plugin rows instead of soft-deleting (`isRemoved = true`). SQLite `ON DELETE CASCADE` automatically removes the related `thumbnail`, `userData`, and `scanRecord` rows. The JPEG file is also deleted from disk.
- **`DatabaseSetup.fetchAllPlugins`** — now filters `isRemoved = false` to guard against stale soft-deleted rows left by older builds.

### Fixed
- **Ghost entries after plugin removal** — `PluginEnumerator` now checks `FileManager.fileExists(atPath:)` for every component URL before accepting it. `AVAudioUnitComponentManager` caches its registry and does not immediately reflect bundle deletions; the file-system check ensures components whose `.component` bundle is gone from disk are excluded from the installed list and therefore cleaned up on the next launch.

---

## Next steps / known limitations

- **List view double-click / Return** — opening the detail popover from a selected list row is stubbed (`// TODO`); needs a `primaryAction` handler on the `Table`.
- **`isRemoved` column** — now unused (hard-delete replaced soft-delete). A future migration could drop the column and its index to keep the schema clean.
- **ThumbnailCache eviction** — removed plugins are deleted from the DB and disk but their `NSImage` may linger in the in-memory `ThumbnailCache` until the app restarts. Low priority since the plugin row no longer appears in the gallery.
- **`.gitignore`** — `xcuserdata/`, `*.xcuserstate`, and `.DS_Store` should be ignored; no `.gitignore` is present in the repo yet.
