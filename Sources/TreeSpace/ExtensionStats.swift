import Foundation

struct ExtensionStat: Identifiable {
    let id: String
    let ext: String        // e.g. "mp4", or "(none)"
    let count: Int
    let totalSize: Int64
}

enum ExtensionAggregator {
    static func stats(from root: FileNode) -> [ExtensionStat] {
        var map: [String: (count: Int, size: Int64)] = [:]
        walk(node: root, map: &map)
        return map
            .map { ExtensionStat(id: $0.key, ext: $0.key, count: $0.value.count, totalSize: $0.value.size) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    /// All files (across subtree) whose extension matches `ext`, sorted by size desc.
    static func files(with ext: String, from root: FileNode) -> [FileNode] {
        var out: [FileNode] = []
        collect(node: root, ext: ext, into: &out)
        return out.sorted { $0.size > $1.size }
    }

    private static func walk(node: FileNode, map: inout [String: (count: Int, size: Int64)]) {
        if !node.isDirectory {
            let key = node.fileExtension.isEmpty ? "(none)" : node.fileExtension
            var entry = map[key] ?? (0, 0)
            entry.count += 1
            entry.size += node.size
            map[key] = entry
            return
        }
        node.children?.forEach { walk(node: $0, map: &map) }
    }

    private static func collect(node: FileNode, ext: String, into out: inout [FileNode]) {
        if !node.isDirectory {
            let key = node.fileExtension.isEmpty ? "(none)" : node.fileExtension
            if key == ext { out.append(node) }
            return
        }
        node.children?.forEach { collect(node: $0, ext: ext, into: &out) }
    }
}
