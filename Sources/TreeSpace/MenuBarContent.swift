import SwiftUI
import AppKit

/// Drop-down rendered by the optional `MenuBarExtra`. Compact enough
/// for a menu, but covers the common need: see the latest size, kick
/// off a rescan, reopen the window, or quit.
struct MenuBarContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let root = state.root {
            Text(root.name)
            Text(ByteCountFormatter.string(fromByteCount: root.size, countStyle: .file))
            if let scanned = state.scanCompletedAt {
                Text("Last scan: \(scanned.formatted(.relative(presentation: .named)))")
            } else if state.isScanning {
                Text("Scanning…")
            }
        } else if state.isScanning {
            Text("Scanning…")
        } else {
            Text("No scan yet")
        }

        Divider()

        Button("Rescan Now") {
            state.rescan()
        }
        .disabled(state.rootURL == nil || state.isScanning)

        Button("Show Window") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }

        Divider()

        Button("Quit TreeSpace") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
