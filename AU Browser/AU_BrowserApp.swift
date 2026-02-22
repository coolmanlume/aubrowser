// AU Browser/AU_BrowserApp.swift

import AUBrowserCore
import SwiftUI

@main
struct AU_BrowserApp: App {

    @StateObject private var store       = PluginStore()
    @StateObject private var scanManager = ScanQueueManager(
        helperURL: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CaptureHelper")
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(scanManager)
                .frame(minWidth: 720, minHeight: 500)
        }
        .commands {
            AUBrowserCommands()
        }
        .defaultSize(width: 1100, height: 700)
    }
}
