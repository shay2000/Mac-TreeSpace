# TreeSpace

A native SwiftUI Mac app that shows what's eating your disk — like TreeSize for Windows or Disk Inventory X, but minimal and yours to hack on.

## Features

- **Size-sorted tree**: expandable folder view with per-row bars showing each item's share of the root.
- **By Extension**: totals grouped by file type — tap a row to list every matching file sorted by size.
- **Find Duplicates**: groups files by size, then screens with a 64 KB head-hash, then confirms with full SHA-256. Shows wasted space per group.
- **Reveal in Finder / Move to Trash**: right-click any row, or use the buttons in the duplicates view.

Files are measured using their allocated size on disk (same number Finder's Get Info shows for "Size on disk"). Symlinks are skipped to avoid cycles. Bundles like `.app` are treated as single items.

## Running it

You need Xcode (or at least the command-line developer tools) on a Mac running macOS 13 or later.

### Option A — Open in Xcode

1. Double-click `Package.swift`, or in Xcode: **File → Open…** and select `Package.swift`.
2. Hit the run button (⌘R).

### Option B — Command line

```bash
cd TreeSpace
swift run
```

The first build takes a minute while SwiftPM pulls toolchains.

### First-time permission prompt

macOS will prompt the app for access the first time you pick a folder that macOS considers sensitive (Desktop, Documents, Downloads). Click Allow. If you want to scan `~/Library` or the whole home folder, you'll need to grant the app **Full Disk Access** in **System Settings → Privacy & Security → Full Disk Access** — add the built binary (or Xcode itself, if running from there).

## How it works

- `Scanner.swift` — single-pass recursive directory walk using `FileManager.contentsOfDirectory` with resource keys. Accumulates sizes on the way back up.
- `DuplicateFinder.swift` — three-stage filter: same-size → same-first-64KB-hash → same-SHA256. Uses `CryptoKit`.
- `FileNode.swift` — reference-type tree so SwiftUI doesn't copy it. `OutlineGroup` uses `sortedChildren` for expansion.
- `AppState.swift` — scan/dup work runs on a background `DispatchQueue`, posts throttled progress back to the main actor.

## Tweaking it

- **Minimum duplicate size**: `DuplicateFinder.find(..., minSize:)` defaults to 64 KB. Lower it if you want to catch smaller junk.
- **Hidden files**: toggle `.skipsHiddenFiles` in `Scanner.swift`.
- **Bundle handling**: remove the `isPackage` check in `Scanner.swift` if you want to drill into `.app` contents.
- **Color thresholds**: `NodeRow.barColor` controls when bars turn orange/red.

## File layout

```
TreeSpace/
  Package.swift
  README.md
  Sources/TreeSpace/
    TreeSpaceApp.swift       # @main entry + menu commands
    AppState.swift           # ObservableObject, scan/dup orchestration
    FileNode.swift           # tree model
    Scanner.swift            # recursive sizer
    DuplicateFinder.swift    # SHA-256 duplicate detection
    ExtensionStats.swift     # group-by-extension aggregator
    ContentView.swift        # split view + toolbar + sidebar
    TreeView.swift           # outline tree + row + file icon
    ExtensionsView.swift     # extension totals + file list
    DuplicatesView.swift     # duplicate groups
```
