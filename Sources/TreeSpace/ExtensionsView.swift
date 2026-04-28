import SwiftUI
import AppKit

struct ExtensionsView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: String?

    var stats: [ExtensionStat] {
        guard let root = state.root else { return [] }
        return ExtensionAggregator.stats(from: root)
    }

    var body: some View {
        if state.root == nil {
            EmptyStateView()
        } else {
            HSplitView {
                // Left: extension totals
                VStack(alignment: .leading, spacing: 0) {
                    Text("Totals by Extension")
                        .font(.headline)
                        .padding([.horizontal, .top])
                    Table(stats, selection: $selected) {
                        TableColumn("Extension") { stat in
                            HStack {
                                Text(".\(stat.ext)").fontWeight(.medium)
                            }
                        }
                        .width(min: 80, ideal: 100)
                        TableColumn("Files") { stat in
                            Text("\(stat.count)").monospacedDigit()
                        }
                        .width(min: 60, ideal: 70)
                        TableColumn("Total Size") { stat in
                            Text(ByteCountFormatter.string(fromByteCount: stat.totalSize, countStyle: .file))
                                .monospacedDigit()
                        }
                        .width(min: 100, ideal: 120)
                    }
                }
                .frame(minWidth: 280)

                // Right: files matching selected extension
                VStack(alignment: .leading, spacing: 0) {
                    Text(selected.map { "Files with .\($0)" } ?? "Select an extension")
                        .font(.headline)
                        .padding([.horizontal, .top])

                    if let ext = selected, let root = state.root {
                        let files = ExtensionAggregator.files(with: ext, from: root)
                        List(files) { node in
                            HStack(spacing: 14) {
                                FileIcon(url: node.url, isDirectory: false)
                                    .frame(width: 22, height: 22)
                                    .padding(.leading, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name).lineLimit(1)
                                    Text(node.url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 16)
                                Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                                    .monospacedDigit()
                                    .padding(.trailing, 4)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                                }
                            )
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                                }
                                Button(role: .destructive) {
                                    confirmTrash(node.url)
                                } label: {
                                    Text("Move to Trash…")
                                }
                            }
                        }
                    } else {
                        Spacer()
                        Text("Pick a row on the left to list matching files.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .frame(minWidth: 320)
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
}
