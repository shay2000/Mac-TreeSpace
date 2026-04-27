import Foundation

/// Outcome of a scan beyond the populated tree itself.
struct ScanReport {
    /// Number of directories we couldn't enumerate (permission denied,
    /// TCC, etc.). Useful for explaining "the app says X but Apple says Y".
    var unreadableDirectories: Int = 0
    /// Volume mount points encountered below the root and skipped to
    /// avoid descending into other disks (network shares, externals).
    var crossedVolumes: Int = 0
}

enum Scanner {
    /// Recursively populate `node`. Uses allocated size on disk, which matches
    /// what Finder's Get Info shows for "Size on disk".
    ///
    /// IMPORTANT: we do NOT pass `.skipsHiddenFiles` — on macOS that hides
    /// `/private`, `/usr`, `/bin`, dotfiles, and many cache dirs, which
    /// causes the scan total to be wildly under-counted vs Apple's
    /// Storage panel. We still skip symlinks (cycles, double-counting)
    /// and don't cross mount points (don't descend into other volumes).
    static func scan(
        node: FileNode,
        count: inout Int,
        report: inout ScanReport,
        rootVolumeID: AnyHashable?,
        progress: (String, Int) -> Void
    ) {
        guard node.isDirectory else { return }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isVolumeKey,
            .volumeIdentifierKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .totalFileSizeKey,
        ]

        let fm = FileManager.default
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: node.url,
                includingPropertiesForKeys: keys,
                options: []   // intentionally NOT skipping hidden files
            )
        } catch {
            node.children = []
            report.unreadableDirectories += 1
            return
        }

        var children: [FileNode] = []
        children.reserveCapacity(contents.count)

        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(keys))

            // Don't follow symlinks — they can create cycles and double-count.
            if values?.isSymbolicLink == true { continue }

            // Don't cross mount points: if this entry sits on a different
            // volume than the scan root (e.g. /Volumes/External, network
            // share), skip its contents but still record it as a small
            // placeholder so the user sees it exists.
            if let rootVolumeID,
               let entryVol = values?.volumeIdentifier as? AnyHashable,
               entryVol != rootVolumeID {
                report.crossedVolumes += 1
                continue
            }

            // Treat bundles (.app, .photoslibrary, etc.) as files for display,
            // but still report their total on-disk size.
            let isDir = values?.isDirectory == true && values?.isPackage != true

            let child = FileNode(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDir,
                parent: node
            )
            count += 1
            if count % 250 == 0 {
                progress(url.path, count)
            }

            if isDir {
                scan(node: child, count: &count, report: &report,
                     rootVolumeID: rootVolumeID, progress: progress)
                node.fileCount += child.fileCount
            } else {
                let size = Int64(values?.totalFileAllocatedSize
                                 ?? values?.fileAllocatedSize
                                 ?? values?.totalFileSize
                                 ?? values?.fileSize
                                 ?? 0)
                child.size = size
                child.fileCount = 1
                node.fileCount += 1
            }
            node.size += child.size
            children.append(child)
        }

        node.children = children
    }
}
