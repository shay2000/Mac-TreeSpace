import SwiftUI
import AppKit

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    private var shouldShowCoverage: Bool {
        // Show whenever we know the volume's used capacity, since users
        // most often misread "the app says X" without context.
        state.volumeTotalCapacity != nil && state.volumeAvailableCapacity != nil
    }

    var body: some View {
        Group {
            if let root = state.root {
                ScrollView {
                    VStack(spacing: 12) {
                        OverviewCard(root: root, state: state)
                        if shouldShowCoverage {
                            CoverageCard(root: root, state: state)
                        }
                        if !state.insights.isEmpty {
                            InsightsSection(insights: state.insights)
                        }
                        if state.previousSnapshot != nil && !state.changes.isEmpty {
                            ChangesSection(
                                previousAt: state.previousSnapshot!.timestamp,
                                changes: state.changes
                            )
                        }
                        if !state.top10Items.isEmpty {
                            TopItemsSection(items: state.top10Items, baseSize: max(root.size, 1))
                        }
                    }
                    .padding(16)
                }
            } else if state.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning \(state.scannedCount) items…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView()
            }
        }
    }
}

// MARK: - Overview card

private struct OverviewCard: View {
    let root: FileNode
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.fill")
                    .font(.body)
                    .foregroundStyle(.tint)
                Text(root.name)
                    .font(.headline)
                Spacer()
                if let prev = state.previousSnapshot {
                    Text("Last scan \(prev.timestamp.relativeShort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("First scan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(root.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ByteCountFormatter.string(fromByteCount: root.size, countStyle: .file))
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                if let delta = state.totalDelta, let prev = state.previousSnapshot {
                    DeltaBadge(delta: delta, since: prev.timestamp)
                }
                Spacer()
                StatPill(systemImage: "doc.fill",
                         text: "\(root.fileCount.formatted()) files")
                StatPill(systemImage: "folder.fill",
                         text: "\(state.directoryCount.formatted()) folders")
            }
            .padding(.top, 2)

            if let children = root.children, !children.isEmpty {
                StackedBreakdownBar(children: children, total: max(root.size, 1))
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardChrome())
    }
}

private struct DeltaBadge: View {
    let delta: Int64
    let since: Date

    var body: some View {
        let positive = delta > 0
        let isNoise = abs(delta) < 1_000_000
        let color: Color = isNoise ? .secondary : (positive ? .red : .green)
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let sign  = positive ? "+" : "−"

        HStack(spacing: 4) {
            Image(systemName: arrow)
                .font(.caption.bold())
            Text(isNoise
                 ? "no change since \(since.relativeShort)"
                 : "\(sign)\(ByteCountFormatter.string(fromByteCount: abs(delta), countStyle: .file)) since \(since.relativeShort)")
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }
}

private struct StatPill: View {
    let systemImage: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}

// MARK: - Coverage card (explains why our number != Apple's)

private struct CoverageCard: View {
    let root: FileNode
    let state: AppState

    private var volumeUsed: Int64? {
        guard let total = state.volumeTotalCapacity,
              let avail = state.volumeAvailableCapacity else { return nil }
        return max(0, total - avail)
    }

    private var coveragePercent: Double? {
        guard let used = volumeUsed, used > 0 else { return nil }
        return min(1.0, Double(root.size) / Double(used))
    }

    private var gapBytes: Int64? {
        guard let used = volumeUsed else { return nil }
        return max(0, used - root.size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("Volume coverage").font(.subheadline).fontWeight(.semibold)
                Spacer()
                if let pct = coveragePercent {
                    Text("\(Int(pct * 100))% accounted for")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Stacked bar: scanned vs everything else on the volume.
            if let used = volumeUsed, used > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        Color.accentColor
                            .frame(width: max(2, geo.size.width * CGFloat(root.size) / CGFloat(used)))
                        if let gap = gapBytes, gap > 0 {
                            Color.secondary.opacity(0.3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .frame(height: 10)

                HStack(spacing: 14) {
                    LegendDot(color: .accentColor,
                              label: "Scanned",
                              size: root.size)
                    if let gap = gapBytes, gap > 0 {
                        LegendDot(color: .secondary.opacity(0.4),
                                  label: "Not in scan",
                                  size: gap)
                    }
                    if let total = state.volumeTotalCapacity {
                        Text("of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) volume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            // Plain-language explanation. Only show when there's a real gap
            // worth talking about (>500 MB).
            if let gap = gapBytes, gap > 500_000_000 {
                Text(reasonsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.unreadableDirectories > 0 || state.crossedVolumes > 0 {
                HStack(spacing: 10) {
                    if state.unreadableDirectories > 0 {
                        Label("\(state.unreadableDirectories.formatted()) unreadable",
                              systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if state.crossedVolumes > 0 {
                        Label("\(state.crossedVolumes) other volume\(state.crossedVolumes == 1 ? "" : "s") skipped",
                              systemImage: "externaldrive.badge.minus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardChrome())
    }

    private var reasonsText: String {
        var parts: [String] = []
        parts.append("Apple's Storage panel and TreeSpace can disagree by tens of GB.")
        parts.append("Things TreeSpace can't see: APFS local snapshots (Time Machine), purgeable iCloud cache, system reserved space, and folders macOS won't let it open without granting Full Disk Access in System Settings → Privacy & Security.")
        if state.unreadableDirectories > 0 {
            parts.append("Granting Full Disk Access usually closes most of the gap.")
        }
        return parts.joined(separator: " ")
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let size: Int64
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct StackedBreakdownBar: View {
    let children: [FileNode]
    let total: Int64

    private static let palette: [Color] = [
        .blue, .purple, .pink, .orange, .yellow, .green, .teal, .indigo,
    ]

    var body: some View {
        let sorted = children.sorted { $0.size > $1.size }
        let top    = Array(sorted.prefix(8))
        let other  = sorted.dropFirst(8).reduce(Int64(0)) { $0 + $1.size }

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(top.enumerated()), id: \.offset) { idx, child in
                        Self.palette[idx % Self.palette.count]
                            .frame(width: max(2, geo.size.width * CGFloat(child.size) / CGFloat(total)))
                    }
                    if other > 0 {
                        Color.secondary.opacity(0.3)
                            .frame(width: max(2, geo.size.width * CGFloat(other) / CGFloat(total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)],
                      alignment: .leading, spacing: 3) {
                ForEach(Array(top.enumerated()), id: \.offset) { idx, child in
                    LegendRow(color: Self.palette[idx % Self.palette.count],
                              name: child.name, size: child.size)
                }
                if other > 0 {
                    LegendRow(color: .secondary.opacity(0.3),
                              name: "Other", size: other)
                }
            }
        }
    }

    private struct LegendRow: View {
        let color: Color
        let name: String
        let size: Int64
        var body: some View {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
    }
}

// MARK: - Insights section

private struct InsightsSection: View {
    let insights: [InsightSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Storage Insights").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("\(insights.count) categor\(insights.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)],
                      spacing: 10) {
                ForEach(insights) { InsightCard(summary: $0) }
            }
        }
    }
}

private struct InsightCard: View {
    @EnvironmentObject var state: AppState
    let summary: InsightSummary
    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            CategoryDetailView(summary: summary)
                .environmentObject(state)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: summary.category.icon)
                    .font(.body)
                    .foregroundStyle(summary.category.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.category.label).fontWeight(.semibold).font(.subheadline)
                    Text(summary.category.blurb)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteCountFormatter.string(fromByteCount: summary.totalSize, countStyle: .file))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                Text("· \(summary.count) item\(summary.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !summary.items.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(summary.items.prefix(3)) { hit in
                        HStack {
                            Text(prettyPath(hit.url))
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text(ByteCountFormatter.string(fromByteCount: hit.size, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if summary.count > 3 {
                        HStack {
                            Text("Show all \(summary.count) →")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(CardChrome())
    }

    /// Show the full path with `~` substituted for the user's home, so
    /// two same-named folders in different locations (e.g. two
    /// `…/Youtube Podcast Sync/build` dirs in different projects) can't
    /// render as the same string. The Text using this has
    /// `.lineLimit(1).truncationMode(.middle)` so long paths still fit.
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

// MARK: - Changes section

private struct ChangesSection: View {
    let previousAt: Date
    let changes: [ChangedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("What changed").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("vs \(previousAt.relativeShort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.element.id) { idx, c in
                    ChangeRow(change: c)
                    if idx < changes.count - 1 {
                        Divider().padding(.leading, 32)
                    }
                }
            }
            .padding(.vertical, 2)
            .modifier(CardChrome())
        }
    }
}

private struct ChangeRow: View {
    let change: ChangedItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(change.name).lineLimit(1).font(.subheadline)
                Text(change.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Text(deltaText)
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(iconColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            let url = URL(fileURLWithPath: change.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        })
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: change.path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(change.path, forType: .string)
            }
        }
    }

    private var iconName: String {
        switch change.kind {
        case .grew:    return "arrow.up.right.circle.fill"
        case .shrank:  return "arrow.down.right.circle.fill"
        case .new:     return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch change.kind {
        case .grew, .new:        return .red
        case .shrank, .removed:  return .green
        }
    }

    private var deltaText: String {
        let s = ByteCountFormatter.string(fromByteCount: change.absDelta, countStyle: .file)
        switch change.kind {
        case .grew:    return "+\(s)"
        case .shrank:  return "−\(s)"
        case .new:     return "new · \(ByteCountFormatter.string(fromByteCount: change.newSize ?? 0, countStyle: .file))"
        case .removed: return "removed · \(ByteCountFormatter.string(fromByteCount: change.oldSize ?? 0, countStyle: .file))"
        }
    }
}

// MARK: - Top items section

private struct TopItemsSection: View {
    let items: [FileNode]
    let baseSize: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top 10 Largest").font(.subheadline).fontWeight(.semibold)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, node in
                    TopItemRow(rank: idx + 1, node: node, baseSize: baseSize)
                    if idx < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical, 2)
            .modifier(CardChrome())
        }
    }
}

private struct TopItemRow: View {
    let rank: Int
    let node: FileNode
    let baseSize: Int64

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            FileIcon(url: node.url, isDirectory: node.isDirectory)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).lineLimit(1).font(.subheadline)
                Text(node.url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: max(2, 90 * fraction))
            }
            .frame(width: 90, height: 6)

            Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            NSWorkspace.shared.activateFileViewerSelecting([node.url])
        })
        .contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }

    private var fraction: Double {
        guard baseSize > 0 else { return 0 }
        return min(1.0, Double(node.size) / Double(baseSize))
    }
}

// MARK: - Shared chrome

private struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - Date helper

private extension Date {
    /// Short relative phrase like "2 days ago" / "yesterday" / "5 min ago".
    var relativeShort: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
