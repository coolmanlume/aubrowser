// AU Browser/App/AUBrowserCommands.swift

import SwiftUI
import AUBrowserCore

/// Menu-bar commands for AU Browser.
///
/// Full rescan is triggered via a notification so commands don't need a direct
/// reference to `ScanQueueManager` (which lives in the SwiftUI environment).
struct AUBrowserCommands: Commands {

    var body: some Commands {
        CommandMenu("Plugins") {
            Button("Rescan All Plugins…") {
                NotificationCenter.default.post(
                    name: .auBrowserRescanAll, object: nil
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let auBrowserRescanAll = Notification.Name("auBrowserRescanAll")
}
