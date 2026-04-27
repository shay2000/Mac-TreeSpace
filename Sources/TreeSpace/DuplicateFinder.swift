import Foundation
import CryptoKit

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    let files: [URL]
    /// Space that would be freed if all but one copy were deleted.
    var wastedBytes: Int64 { Int64(max(0, files.count - 1)) * size }
}

enum DuplicateFinder {
    /// Groups files by size, then by a fast head-hash, then by full SHA-256.
    /// Files smaller than `minSize` are ignored to skip thousands of tiny
    /// identical Info.plist / .DS_Store style files.
    static func find(
        root: FileNode,
        minSize: Int64 = 64 * 1024,
        progress: (String) -> Void
    ) -> [DuplicateGroup] {
        // 1. Collect files by size.
        var bySize: [Int64: [URL]] = [:]
        collect(node: root, minSize: minSize, into: &bySize)

        let candidateSizes = bySize.filter { $0.value.count >= 2 }
        let totalCandidates = candidateSizes.values.reduce(0) { $0 + $1.count }
        progress("Hashing \(totalCandidates) candidate files…")

        var groups: [DuplicateGroup] = []
        var hashed = 0

        for (size, urls) in candidateSizes.sorted(by: { $0.key > $1.key }) {
            // 2. Cheap head-hash first to eliminate obvious non-matches.
            var byHead: [String: [URL]] = [:]
            for url in urls {
                if let h = hashHead(url: url) {
                    byHead[h, default: []].append(url)
                }
                hashed += 1
                if hashed % 25 == 0 {
                    progress("Screening \(hashed)/\(totalCandidates) — \(formatSize(size))")
                }
            }

            // 3. Full hash only for the remaining suspects.
            for (_, maybeDupes) in byHead where maybeDupes.count >= 2 {
                var byFull: [String: [URL]] = [:]
                for url in maybeDupes {
                    if let h = hashFull(url: url) {
                        byFull[h, default: []].append(url)
                    }
                }
                for (_, real) in byFull where real.count >= 2 {
                    groups.append(DuplicateGroup(size: size, files: real))
                }
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private static func collect(node: FileNode, minSize: Int64, into bySize: inout [Int64: [URL]]) {
        if !node.isDirectory {
            if node.size >= minSize {
                bySize[node.size, default: []].append(node.url)
            }
            return
        }
        node.children?.forEach { collect(node: $0, minSize: minSize, into: &bySize) }
    }

    private static func hashHead(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 65_536)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hashFull(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1_048_576)) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
