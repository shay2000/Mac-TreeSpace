import SwiftUI
import AppKit

@main
struct TreeSpaceApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("TreeSpace") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    Self.installAppIcon()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Folder to Scan…") {
                    state.pickFolderAndScan()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("Rescan") {
                    state.rescan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(state.rootURL == nil || state.isScanning)
            }
        }
    }

    /// Load the PNG shipped in Resources and set it as the application icon.
    /// Populates the Dock tile / window proxy icon even though SwiftPM
    /// executables have no Info.plist-driven CFBundleIconFile.
    private static func installAppIcon() {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
