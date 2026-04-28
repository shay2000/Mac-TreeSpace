import SwiftUI
import AppKit

/// Full list of every item that fell into a Storage Insights category.
/// Reached by tapping the corresponding card on the dashboard.
struct CategoryDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let summary: InsightSummary

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: summary.category.icon)
                .font(.title)
                .foregroundStyle(summary.category.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.category.label).font(.title2).fontWeight(.semibold)
                Text(summary.category.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))
                    .font(.title3).fontWeight(.bold).monospacedDigit()
                Text("\(summary.count) item\(summary.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var list: some View {
        List(summary.items) { hit in
            CategoryItemRow(hit: hit, totalSize: summary.totalSize)
                .environmentObject(state)
        }
    }
}

private struct CategoryItemRow: View {
    @EnvironmentObject var state: AppState
    let hit: InsightHit
    let totalSize: Int64

    private var fraction: Double {
        guard totalSize > 0 else { return 0 }
        return min(1.0, Double(hit.size) / Double(totalSize))
    }

    var body: some View {
        HStack(spacing: 8) {
            FileIcon(url: hit.url, isDirectory: hit.isDirectory)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.url.lastPathComponent).font(.subheadline).lineLimit(1)
                Text(prettyPath(hit.url))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(hit.category.tint.opacity(0.7))
                    .frame(width: max(2, 80 * fraction))
            }
            .frame(width: 80, height: 6)
            Text(ByteCountFormatter.string(fromByteCount: hit.size, countStyle: .file))
                .font(.caption.monospacedDigit())
                .frame(width: 78, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([hit.url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button(role: .destructive) {
                confirmTrash(hit.url)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Move to Trash")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([hit.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hit.url.path, forType: .string)
            }
            Divider()
            Button("Move to Trash…", role: .destructive) {
                confirmTrash(hit.url)
            }
        }
    }

    private func confirmTrash(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Move \"\(url.lastPathComponent)\" to Trash?"
        alert.informativeText = url.path
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await state.moveToTrash(url) }
        }
    }

    private func prettyPath(_ url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
