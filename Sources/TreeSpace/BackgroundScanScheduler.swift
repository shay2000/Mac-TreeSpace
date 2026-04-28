import Foundation

/// Wraps `NSBackgroundActivityScheduler` so a scan can fire on a low,
/// energy-aware schedule. macOS coalesces these activities and defers
/// them on battery / low-power / system busy — we just declare the
/// intent and let the OS pick the moment.
///
/// `reconcile()` reads the current settings from `UserDefaults` and
/// either tears down the scheduler (if disabled) or replaces it with
/// one configured for the chosen interval. Always call from the main
/// thread; `AppState` is `@MainActor` so its callers already are.
final class BackgroundScanScheduler {
    private var scheduler: NSBackgroundActivityScheduler?
    weak var appState: AppState?

    static let enabledKey = "periodicRescanEnabled"
    static let intervalHoursKey = "periodicRescanIntervalHours"
    static let activityIdentifier = "com.treespace.periodic-rescan"

    func reconcile() {
        scheduler?.invalidate()
        scheduler = nil

        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        guard enabled else { return }

        let storedHours = UserDefaults.standard.integer(forKey: Self.intervalHoursKey)
        let hours = storedHours > 0 ? storedHours : 6

        let s = NSBackgroundActivityScheduler(identifier: Self.activityIdentifier)
        s.repeats = true
        s.interval = TimeInterval(hours * 3600)
        s.tolerance = s.interval * 0.25
        s.qualityOfService = .utility
        s.schedule { [weak self] completion in
            // Hop to MainActor to touch AppState; complete the activity
            // immediately (we don't wait for the scan to finish — the
            // scheduler's job is to fire periodically, not to track
            // long-running work).
            Task { @MainActor in
                if let app = self?.appState, !app.isScanning, let url = app.rootURL {
                    app.scan(url: url, qos: .utility, isBackground: true)
                }
                completion(.finished)
            }
        }
        scheduler = s
    }

    func invalidate() {
        scheduler?.invalidate()
        scheduler = nil
    }
}
