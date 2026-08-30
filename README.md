# AU Browser

A native macOS app that browses every installed Audio Unit (AU) plugin, with auto-captured thumbnails of each plugin's GUI and rich filtering/sorting by name, manufacturer, type, install date, and user tags.

## How it works

Plugin discovery is cross-referenced against Apple's `auval` cache (`~/Library/Preferences/com.apple.audiounits.cache`) so only Logic-approved, validated plugins are queued — broken or untested components never reach the scan queue. Each plugin's GUI is captured by spawning an isolated `CaptureHelper` subprocess per plugin, which instantiates the AU, renders its view offscreen, and writes a JPEG; a hard 20s timeout and process isolation mean a crashing or hanging plugin can't take down the scan or the app. Metadata and scan history are stored locally in SQLite via GRDB, so search/filter/sort is instant.

## Requirements

- macOS 14.0+
- Xcode 15+
- App Sandbox must stay **disabled** — required for out-of-process AU instantiation

## Building

Open `AU Browser.xcodeproj` in Xcode. Swift Package Manager dependencies (GRDB) resolve automatically. Build the `AU Browser` scheme — it depends on `CaptureHelper` and `AUBrowserCore`, which are built first and the helper binary is embedded into `AU Browser.app/Contents/Helpers/`.

## Project structure

Three targets:

| Target | Role |
|---|---|
| `AU Browser` | SwiftUI app — views and commands only, no business logic |
| `AUBrowserCore` | Shared framework — GRDB schema/migrations, data models, `PluginEnumerator`, `ScanQueueManager`, `PluginStore` |
| `CaptureHelper` | Command-line executable spawned per plugin to capture its GUI, isolated from the main app |

```
AU Browser/
├── App/                  entry point, menu commands
├── Views/
│   ├── Sidebar/          type/manufacturer/tag filters
│   ├── Toolbar/          search, sort, scan progress
│   ├── Gallery/          grid + list views, detail popover, selection bar
│   └── Shared/           skeleton/placeholder views
└── Assets.xcassets

AUBrowserCore/
├── Database/             GRDB models + migrations
├── Scanning/             enumeration + scan queue
├── Store/                query layer, thumbnail cache
└── Types/                sort order, view mode, filter enums

CaptureHelper/
└── main.swift            offscreen AU render + JPEG capture
```

See [`PLANNING.md`](PLANNING.md) for the full design spec (database schema, thumbnail spec, `CaptureHelper` exit codes, UI behaviour details).

## Status

Actively developed — see [`CHANGELOG.md`](CHANGELOG.md) for recent changes and known limitations (e.g. list-view double-click to open detail is stubbed, `isRemoved` column is now dead weight after the switch to hard deletes).

## License

MIT — see [`LICENSE`](LICENSE).
