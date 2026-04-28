import Foundation

extension URL {
    /// Friendly label suitable for display in the UI. For volume roots
    /// this returns the user-visible name (e.g. "Macintosh HD") rather
    /// than the raw path component "/". Falls back to lastPathComponent,
    /// then to the full path, so the result is always non-empty.
    var displayName: String {
        if let name = (try? resourceValues(forKeys: [.localizedNameKey]))?.localizedName,
           !name.isEmpty {
            return name
        }
        let last = lastPathComponent
        return last.isEmpty ? path : last
    }
}
