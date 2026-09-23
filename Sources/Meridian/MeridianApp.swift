import AppKit
import SwiftUI

@main
struct MeridianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ClockStore()

    var body: some Scene {
        MenuBarExtra {
            ClockPanel(store: store)
        } label: {
            let title = store.menuBarTitle
            if title.isEmpty {
                Image(systemName: "clock")
            } else {
                Text(title).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, even when launched via `swift run` without the Info.plist.
        NSApp.setActivationPolicy(.accessory)
    }
}
