import Foundation
import CryptoKit

/// Compact persistent snapshot of a scan. Only the largest N items are
/// kept; that's enough to compute a meaningful "what changed" diff
/// without writing a 50k-row tree to disk every scan.
struct Snapshot: Codable {
    let rootPath: String
    let timestamp: Date
    let totalSize: Int64
    let fileCount: Int
    let topItems: [Item]

    struct Item: Codable, Hashable {
        let path: String
        let size: Int64
        let isDirectory: Bool
    }
}

enum SnapshotStore {
    /// `~/Library/Application Support/TreeSpace/Snapshots/`.
    static var directory: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = support.appendingPathComponent("TreeSpace/Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// One JSON per root path, keyed by a SHA-256 prefix so funky
    /// characters in paths don't break filenames.
    static func url(for rootPath: String) -> URL {
        let digest = SHA256.hash(data: Data(rootPath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(String(hex.prefix(16)) + ".json")
    }

    static func loadLatest(for rootPath: String) -> Snapshot? {
        let url = url(for: rootPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url(for: snapshot.rootPath), options: .atomic)
    }

    /// Delete the snapshot for a single root path. Returns true if a file
    /// was actually removed (i.e. there was something to delete).
    @discardableResult
    static func delete(for rootPath: String) -> Bool {
        let url = url(for: rootPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    /// Delete every stored snapshot. Returns the count removed.
    @discardableResult
    static func deleteAll() -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return 0
        }
        var n = 0
        for entry in entries where entry.pathExtension.lowercased() == "json" {
            if (try? fm.removeItem(at: entry)) != nil { n += 1 }
        }
        return n
    }

    /// Lightweight listing of all stored snapshots for management UI.
    static func listAll() -> [Snapshot] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [Snapshot] = []
        for entry in entries where entry.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: entry),
               let snap = try? decoder.decode(Snapshot.self, from: data) {
                out.append(snap)
            }
        }
        return out.sorted { $0.timestamp > $1.timestamp }
    }

    /// Walk the tree and pick the `topN` largest nodes by size, keeping a
    /// mix of files and directories. Includes the root.
    static func makeFromTree(root: FileNode, topN: Int = 250) -> Snapshot {
        var heap: [Snapshot.Item] = []
        heap.reserveCapacity(2048)

        func visit(_ node: FileNode) {
            heap.append(Snapshot.Item(path: node.url.path, size: node.size, isDirectory: node.isDirectory))
            node.children?.forEach(visit)
        }
        visit(root)

        heap.sort { $0.size > $1.size }
        let top = Array(heap.prefix(topN))

        return Snapshot(
            rootPath: root.url.path,
            timestamp: Date(),
            totalSize: root.size,
            fileCount: root.fileCount,
            topItems: top
        )
    }
}

// MARK: - Diff

struct ChangedItem: Identifiable {
    enum Kind { case grew, shrank, new, removed }

    let id: String      // path used as identity
    let path: String
    let oldSize: Int64?
    let newSize: Int64?
    let isDirectory: Bool

    var name: String { (path as NSString).lastPathComponent }
    var delta: Int64 { (newSize ?? 0) - (oldSize ?? 0) }
    var absDelta: Int64 { abs(delta) }

    var kind: Kind {
        if oldSize == nil { return .new }
        if newSize == nil { return .removed }
        return delta >= 0 ? .grew : .shrank
    }
}

enum SnapshotDiff {
    /// Returns up to `limit` items sorted by absolute size delta. Skips
    /// noise (< minDelta) and the root itself.
    static func compute(
        previous: Snapshot,
        current: Snapshot,
        minDelta: Int64 = 5_000_000,   // 5 MB
        limit: Int = 25
    ) -> [ChangedItem] {
        struct Entry { var old: Int64?; var new: Int64?; var isDir: Bool }
        var byPath: [String: Entry] = [:]

        for item in previous.topItems {
            byPath[item.path] = Entry(old: item.size, new: nil, isDir: item.isDirectory)
        }
        for item in current.topItems {
            var e = byPath[item.path] ?? Entry(old: nil, new: nil, isDir: item.isDirectory)
            e.new = item.size
            e.isDir = item.isDirectory
            byPath[item.path] = e
        }

        var out: [ChangedItem] = []
        for (path, e) in byPath {
            if path == current.rootPath || path == previous.rootPath { continue }
            let delta = (e.new ?? 0) - (e.old ?? 0)
            if abs(delta) < minDelta { continue }
            out.append(ChangedItem(
                id: path, path: path,
                oldSize: e.old, newSize: e.new,
                isDirectory: e.isDir
            ))
        }
        return Array(out.sorted { $0.absDelta > $1.absDelta }.prefix(limit))
    }
}
