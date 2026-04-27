import SwiftUI
import AppKit

/// Flat row produced by walking the tree with respect to the user's
/// current expansion set. Each row knows its depth so we can indent.
struct FlatRow: Identifiable {
    let id: UUID
    let node: FileNode
    let depth: Int
}

struct TreeView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: UUID?
    @State private var expanded: Set<UUID> = []

    var body: some View {
        Group {
            if let root = state.root {
                let rows = flatten(root: root, expanded: expanded)
                List(rows, selection: $selection) { row in
                    TreeRow(
                        node: row.node,
                        depth: row.depth,
                        baseSize: max(root.size, 1),
                        isRoot: row.depth == 0,
                        isExpanded: expanded.contains(row.node.id),
                        toggle: { toggle(row.node.id) }
                    )
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            } else if state.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning \(state.scannedCount) items…")
                        .foregroundStyle(.secondary)
                    Text(state.progressText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView()
            }
        }
    }

    // MARK: - Expansion

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) }
        else { expanded.insert(id) }
    }

    // MARK: - Flatten

    /// Depth 0 = root. Root's children always rendered (root is always expanded).
    /// For descendants, only emit children when the parent is in `expanded`.
    private func flatten(root: FileNode, expanded: Set<UUID>) -> [FlatRow] {
        var result: [FlatRow] = []
        result.append(FlatRow(id: root.id, node: root, depth: 0))
        if let children = root.sortedChildren {
            for child in children {
                visit(child, depth: 1, expanded: expanded, into: &result)
            }
        }
        return result
    }

    private func visit(_ node: FileNode, depth: Int, expanded: Set<UUID>, into result: inout [FlatRow]) {
        result.append(FlatRow(id: node.id, node: node, depth: depth))
        guard expanded.contains(node.id), let children = node.sortedChildren else { return }
        for child in children {
            visit(child, depth: depth + 1, expanded: expanded, into: &result)
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No folder scanned yet")
                .font(.title2)
            Text("Pick a folder to see what's using your disk space.")
                .foregroundStyle(.secondary)
            Button {
                state.pickFolderAndScan()
            } label: {
                Label("Choose Folder…", systemImage: "folder.badge.plus")
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tree row

struct TreeRow: View {
    let node: FileNode
    let depth: Int
    let baseSize: Int64
    let isRoot: Bool
    let isExpanded: Bool
    let toggle: () -> Void

    private var fraction: Double {
        guard baseSize > 0 else { return 0 }
        return min(1.0, Double(node.size) / Double(baseSize))
    }

    private var hasExpandableChildren: Bool {
        node.isDirectory && (node.children?.isEmpty == false)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Indentation — one "unit" per depth level beyond the root.
            if depth > 1 {
                Color.clear.frame(width: CGFloat(depth - 1) * 16, height: 1)
            }

            // Chevron column (fixed width so everything else aligns across rows).
            chevron
                .frame(width: 16, height: 16)

            // Icon
            FileIcon(url: node.url, isDirectory: node.isDirectory)
                .frame(width: 20, height: 20)

            // Name
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(isRoot ? .semibold : .regular)

            Spacer(minLength: 16)

            // Size-share bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 5)
                    .fill(barColor)
                    .frame(width: max(2, 160 * fraction))
            }
            .frame(width: 160, height: 10)
            .padding(.trailing, 4)

            // Size
            Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)

            // File count
            Text(node.isDirectory ? "\(node.fileCount)" : "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 4)
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
        )
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Button("Open") { NSWorkspace.shared.open(node.url) }
            Divider()
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
            Divider()
            Button(role: .destructive) {
                confirmAndTrash()
            } label: {
                Text("Move to Trash…")
            }
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if isRoot {
            // Root is always "expanded" — no toggle, just an empty placeholder
            // for alignment.
            Color.clear
        } else if hasExpandableChildren {
            Button(action: toggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
        }
    }

    private var barColor: Color {
        if fraction > 0.25 { return .red }
        if fraction > 0.10 { return .orange }
        return .accentColor
    }

    private func confirmAndTrash() {
        let alert = NSAlert()
        alert.messageText = "Move \"\(node.name)\" to Trash?"
        alert.informativeText = node.url.path
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            var trashed: NSURL?
            try? FileManager.default.trashItem(at: node.url, resultingItemURL: &trashed)
        }
    }
}

// MARK: - File-kind icon via NSWorkspace

struct FileIcon: NSViewRepresentable {
    let url: URL
    let isDirectory: Bool

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSWorkspace.shared.icon(forFile: url.path)
    }
}
