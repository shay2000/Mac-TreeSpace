import AppKit

/// Owns AppKit-level app behavior that SwiftUI's App lifecycle doesn't
/// expose directly: keeping the process alive after the last window
/// closes (when menu-bar mode is on) and hiding the Dock icon in that
/// case.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "runInMenuBar")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            // willClose fires before the window leaves the array — defer
            // the check until after the close so isVisible is accurate.
            DispatchQueue.main.async {
                guard UserDefaults.standard.bool(forKey: "runInMenuBar") else { return }
                let hasRealWindow = NSApp.windows.contains { window in
                    guard window.isVisible else { return false }
                    let cls = window.className
                    return !cls.contains("StatusBar") && !cls.contains("MenuBarExtra")
                }
                if !hasRealWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
