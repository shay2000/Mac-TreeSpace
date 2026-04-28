import SwiftUI
import AppKit

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState

    var totalWasted: Int64 {
        state.duplicates.reduce(0) { $0 + $1.wastedBytes }
    }

    var body: some View {
        if state.root == nil {
            EmptyStateView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Duplicate Files")
                            .font(.headline)
                        if !state.duplicates.isEmpty {
                            Text("\(state.duplicates.count) groups — \(ByteCountFormatter.string(fromByteCount: totalWasted, countStyle: .file)) could be freed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !state.duplicateProgress.isEmpty {
                            Text(state.duplicateProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if state.isFindingDuplicates {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        state.findDuplicates()
                    } label: {
                        Label(state.duplicates.isEmpty ? "Scan for Duplicates" : "Rescan",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(state.isFindingDuplicates)
                }
                .padding()

                Divider()

                if state.duplicates.isEmpty && !state.isFindingDuplicates {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No duplicates found yet")
                            .foregroundStyle(.secondary)
                        Text("Click \"Scan for Duplicates\" to start. Files smaller than 64 KB are ignored.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List {
                        ForEach(state.duplicates) { group in
                            DuplicateGroupRow(group: group)
                        }
                    }
                }
            }
        }
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @EnvironmentObject var state: AppState
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(group.files, id: \.self) { url in
                HStack(spacing: 14) {
                    FileIcon(url: url, isDirectory: false)
                        .frame(width: 22, height: 22)
                        .padding(.leading, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent).lineLimit(1)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 16)
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.borderless)
                    Button("Trash") { confirmTrash(url) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .padding(.trailing, 4)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                )
            }
        } label: {
            HStack {
                Text("\(group.files.count) copies")
                    .fontWeight(.semibold)
                Text(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Wasted: \(ByteCountFormatter.string(fromByteCount: group.wastedBytes, countStyle: .file))")
                    .foregroundStyle(.orange)
                    .monospacedDigit()
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
