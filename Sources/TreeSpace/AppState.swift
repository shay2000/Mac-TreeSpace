import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var root: FileNode?
    @Published var rootURL: URL?
    @Published var isScanning = false
    @Published var progressText: String = ""
    @Published var scannedCount: Int = 0

    @Published var duplicates: [DuplicateGroup] = []
    @Published var isFindingDuplicates = false
    @Published var duplicateProgress: String = ""

    // Dashboard state
    @Published var previousSnapshot: Snapshot?
    @Published var insights: [InsightSummary] = []
    @Published var changes: [ChangedItem] = []
    @Published var totalDelta: Int64?
    @Published var scanCompletedAt: Date?
    @Published var directoryCount: Int = 0
    @Published var top10Items: [FileNode] = []

    // Coverage / "why does Apple say a different number" stats
    @Published var unreadableDirectories: Int = 0
    @Published var crossedVolumes: Int = 0
    @Published var volumeTotalCapacity: Int64?
    @Published var volumeAvailableCapacity: Int64?

    private var scanGeneration: Int = 0
    private var dupGeneration: Int = 0

    private let backgroundScheduler = BackgroundScanScheduler()

    init() {
        backgroundScheduler.appState = self
        backgroundScheduler.reconcile()
    }

    /// Re-read the periodic-rescan settings and rebuild the scheduler.
    /// Called from the Settings UI when the toggle or interval changes.
    func reconcileBackgroundScheduler() {
        backgroundScheduler.reconcile()
    }

    // MARK: - Folder picking

    func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to scan"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            scan(url: url)
        }
    }

    func rescan() {
        if let url = rootURL { scan(url: url) }
    }

    /// Called once at launch. If we've already scanned something this
    /// session, do nothing. Otherwise scan the most recently scanned
    /// folder (persisted in UserDefaults) — falling back to "/" so the
    /// user sees something useful on a fresh install.
    func scanIfNeededOnLaunch() {
        guard rootURL == nil else { return }
        let saved = UserDefaults.standard.string(forKey: AppState.lastRootPathKey) ?? ""
        let url: URL
        if !saved.isEmpty, FileManager.default.fileExists(atPath: saved) {
            url = URL(fileURLWithPath: saved)
        } else {
            url = URL(fileURLWithPath: "/")
        }
        scan(url: url)
    }

    static let lastRootPathKey = "lastRootPath"

    // MARK: - Scan

    func scan(url: URL, qos: DispatchQoS.QoSClass = .userInitiated, isBackground: Bool = false) {
        // A background rescan should never preempt a foreground one. The
        // scheduler self-gates on this so the user's manual scan keeps
        // priority.
        if isBackground && isScanning { return }
        scanGeneration += 1
        let gen = scanGeneration
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: AppState.lastRootPathKey)
        root = nil
        duplicates = []
        isScanning = true
        progressText = "Starting…"
        scannedCount = 0

        // Reset dashboard state for the new scan
        previousSnapshot = nil
        insights = []
        changes = []
        totalDelta = nil
        scanCompletedAt = nil
        directoryCount = 0
        top10Items = []
        unreadableDirectories = 0
        crossedVolumes = 0
        volumeTotalCapacity = nil
        volumeAvailableCapacity = nil

        // Capture the volume the user picked so the scanner can avoid
        // crossing into other mounted disks.
        let rootValues = try? url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let rootVolumeID: AnyHashable? = rootValues?.volumeIdentifier as? AnyHashable
        let volTotal: Int64? = (rootValues?.volumeTotalCapacity).map(Int64.init)
        // Use "important usage" available bytes when present — that's the
        // figure Apple's Storage panel uses (excludes purgeable).
        let volAvailable: Int64? = rootValues?.volumeAvailableCapacityForImportantUsage
            ?? (rootValues?.volumeAvailableCapacity).map(Int64.init)

        DispatchQueue.global(qos: qos).async { [weak self] in
            let rootNode = FileNode(url: url, name: url.displayName, isDirectory: true)
            var count = 0
            var report = ScanReport()
            var lastPost = Date()

            Scanner.scan(node: rootNode, count: &count, report: &report,
                         rootVolumeID: rootVolumeID) { path, n in
                let now = Date()
                // throttle main-thread updates
                if now.timeIntervalSince(lastPost) > 0.1 {
                    lastPost = now
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.scanGeneration == gen else { return }
                        self.scannedCount = n
                        self.progressText = path
                    }
                }
            }

            // Post-scan analysis (still on background queue).
            // 1. Load previous snapshot (if any) for diffing.
            // 2. Build new snapshot from the tree and persist it.
            // 3. Detect insight categories.
            // 4. Compute changes vs previous snapshot.
            // 5. Find top 10 largest items and total directory count.
            let previous = SnapshotStore.loadLatest(for: url.path)
            let current = SnapshotStore.makeFromTree(root: rootNode, topN: 250)
            SnapshotStore.save(current)

            let insights = InsightDetector.detect(root: rootNode)
            let changes: [ChangedItem]
            let totalDelta: Int64?
            if let prev = previous {
                changes = SnapshotDiff.compute(previous: prev, current: current)
                totalDelta = current.totalSize - prev.totalSize
            } else {
                changes = []
                totalDelta = nil
            }
            let top10 = TopItems.find(root: rootNode, count: 10)
            let dirCount = TopItems.countDirectories(root: rootNode)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == gen else { return }
                self.root = rootNode
                self.scannedCount = count
                self.isScanning = false
                self.progressText = "Done"

                self.previousSnapshot = previous
                self.insights = insights
                self.changes = changes
                self.totalDelta = totalDelta
                self.directoryCount = dirCount
                self.top10Items = top10
                self.scanCompletedAt = Date()
                self.unreadableDirectories = report.unreadableDirectories
                self.crossedVolumes = report.crossedVolumes
                self.volumeTotalCapacity = volTotal
                self.volumeAvailableCapacity = volAvailable
            }
        }
    }

    // MARK: - Duplicates

    func findDuplicates() {
        guard let root else { return }
        dupGeneration += 1
        let gen = dupGeneration
        isFindingDuplicates = true
        duplicateProgress = "Collecting files…"
        duplicates = []

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = DuplicateFinder.find(root: root) { msg in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.dupGeneration == gen else { return }
                    self.duplicateProgress = msg
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.dupGeneration == gen else { return }
                self.duplicates = found
                self.isFindingDuplicates = false
                self.duplicateProgress = "Found \(found.count) duplicate groups"
            }
        }
    }

    // MARK: - File actions

    @discardableResult
    func moveToTrash(_ url: URL) async -> Bool {
        // Gate every destructive action behind Touch ID / password. Result
        // is cached for ~60s so a batch trash prompts once.
        let ok = await Auth.require(
            reason: "Authenticate to move \"\(url.lastPathComponent)\" to the Trash"
        )
        guard ok else { return false }

        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            return true
        } catch {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "Couldn't move to Trash"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Snapshot management

    /// Returns all snapshots currently persisted on disk, newest first.
    func loadAllSnapshots() -> [Snapshot] {
        SnapshotStore.listAll()
    }

    /// Delete the snapshot baseline for the currently scanned folder.
    /// The next scan will treat that folder as a first-time scan.
    @discardableResult
    func deleteSnapshotForCurrentFolder() -> Bool {
        guard let url = rootURL else { return false }
        let removed = SnapshotStore.delete(for: url.path)
        if removed {
            previousSnapshot = nil
            changes = []
            totalDelta = nil
        }
        return removed
    }

    /// Delete a snapshot for an arbitrary root path (used by the
    /// "Manage Snapshots" sheet). Clears in-memory comparison state if
    /// the deleted snapshot was the one we're currently comparing against.
    @discardableResult
    func deleteSnapshot(for rootPath: String) -> Bool {
        let removed = SnapshotStore.delete(for: rootPath)
        if removed, rootURL?.path == rootPath {
            previousSnapshot = nil
            changes = []
            totalDelta = nil
        }
        return removed
    }

    /// Wipe every saved snapshot. Returns the number removed. Also clears
    /// the in-memory comparison state since whatever we were comparing
    /// against is gone now.
    @discardableResult
    func deleteAllSnapshots() -> Int {
        let n = SnapshotStore.deleteAll()
        previousSnapshot = nil
        changes = []
        totalDelta = nil
        return n
    }
}
