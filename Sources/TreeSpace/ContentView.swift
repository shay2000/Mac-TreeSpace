import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SidebarTab? = .dashboard
    @State private var showSnapshotsSheet = false

    enum SidebarTab: String, Hashable, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case tree = "Tree"
        case extensions = "By Extension"
        case duplicates = "Duplicates"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .dashboard: return "chart.bar.doc.horizontal"
            case .tree: return "list.bullet.indent"
            case .extensions: return "doc.richtext"
            case .duplicates: return "doc.on.doc"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("View") {
                    ForEach(SidebarTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
                if let root = state.root {
                    Section("Scan") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(root.name).fontWeight(.medium).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: root.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("\(root.fileCount) files")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            detail
                .toolbar { toolbar }
                .sheet(isPresented: $showSnapshotsSheet) {
                    SnapshotsManagerView()
                        .environmentObject(state)
                        .frame(minWidth: 560, minHeight: 420)
                }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .dashboard {
        case .dashboard:  DashboardView()
        case .tree:       TreeView()
        case .extensions: ExtensionsView()
        case .duplicates: DuplicatesView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                state.pickFolderAndScan()
            } label: {
                Label("Choose Folder", systemImage: "folder.badge.plus")
            }
            Button {
                state.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(state.rootURL == nil || state.isScanning)

            Menu {
                Button("Delete Snapshot for This Folder…") {
                    confirmDeleteCurrentSnapshot()
                }
                .disabled(state.rootURL == nil)

                Divider()

                Button("Manage All Snapshots…") {
                    showSnapshotsSheet = true
                }

                Button("Delete All Snapshots…", role: .destructive) {
                    confirmDeleteAllSnapshots()
                }
            } label: {
                Label("Snapshots", systemImage: "clock.arrow.circlepath")
            }

            if state.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("\(state.scannedCount) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Confirmations

    private func confirmDeleteCurrentSnapshot() {
        let name = state.rootURL?.lastPathComponent ?? "this folder"
        let alert = NSAlert()
        alert.messageText = "Delete snapshot for “\(name)”?"
        alert.informativeText = "The next scan of this folder will start fresh — there will be no “what changed” comparison until you scan it again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            state.deleteSnapshotForCurrentFolder()
        }
    }

    private func confirmDeleteAllSnapshots() {
        let alert = NSAlert()
        alert.messageText = "Delete every saved snapshot?"
        alert.informativeText = "This removes the comparison baseline for every folder you've ever scanned. Folder contents themselves are not touched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = state.deleteAllSnapshots()
        }
    }
}

// MARK: - Snapshots manager sheet

struct SnapshotsManagerView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [Snapshot] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Snapshots").font(.title2).fontWeight(.semibold)
                Spacer()
                Text("\(snapshots.count) total")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            if snapshots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No snapshots yet")
                        .font(.headline)
                    Text("Scan a folder and the next scan will compare against it.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(snapshots, id: \.rootPath) { snap in
                        SnapshotRow(snapshot: snap) {
                            confirmDelete(snap)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    confirmDeleteAll()
                } label: {
                    Label("Delete All", systemImage: "trash")
                }
                .disabled(snapshots.isEmpty)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        snapshots = state.loadAllSnapshots()
    }

    private func confirmDelete(_ snap: Snapshot) {
        let name = (snap.rootPath as NSString).lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Delete snapshot for “\(name)”?"
        alert.informativeText = snap.rootPath
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = state.deleteSnapshot(for: snap.rootPath)
            reload()
        }
    }

    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete every saved snapshot?"
        alert.informativeText = "This removes the comparison baseline for every folder you've ever scanned."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = state.deleteAllSnapshots()
            reload()
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: Snapshot
    let onDelete: () -> Void

    private var name: String { (snapshot.rootPath as NSString).lastPathComponent }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.medium).lineLimit(1)
                Text(snapshot.rootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: snapshot.totalSize, countStyle: .file))
                        .monospacedDigit()
                    Text("·")
                    Text("\(snapshot.fileCount.formatted()) files")
                    Text("·")
                    Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this snapshot")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Reveal Folder in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: snapshot.rootPath)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snapshot.rootPath, forType: .string)
            }
            Divider()
            Button("Delete Snapshot", role: .destructive, action: onDelete)
        }
    }
}
