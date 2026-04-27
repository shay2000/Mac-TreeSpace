import Foundation

/// A node in the scanned file tree. Reference type so the tree doesn't get
/// copied when SwiftUI diffs it.
final class FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0
    var fileCount: Int = 0            // files (not dirs) in subtree
    var children: [FileNode]?         // nil = file, non-nil = directory (possibly empty)
    weak var parent: FileNode?

    init(url: URL, name: String, isDirectory: Bool, parent: FileNode? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.parent = parent
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// For OutlineGroup: nil => leaf (not expandable), non-nil => expandable.
    var sortedChildren: [FileNode]? {
        guard isDirectory else { return nil }
        return (children ?? []).sorted { $0.size > $1.size }
    }
}
