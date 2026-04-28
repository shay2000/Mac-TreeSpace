import Foundation
import LocalAuthentication

/// Touch ID / password gate for destructive operations.
///
/// Wraps `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` so a
/// successful auth is cached for `cacheWindow` seconds — a multi-select
/// trash of N files prompts the user once, not N times. If the machine
/// has no auth method configured (rare on macOS but possible), the gate
/// falls through and allows the action rather than locking the user out
/// of their own files.
@MainActor
enum Auth {
    private static var lastSuccess: Date?
    private static let cacheWindow: TimeInterval = 60

    static func require(reason: String) async -> Bool {
        if let last = lastSuccess, Date().timeIntervalSince(last) < cacheWindow {
            return true
        }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password"
        var error: NSError?
        // No biometrics or password set — don't block; deletion still goes
        // to Trash and is recoverable.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication,
                                                  localizedReason: reason)
            if ok { lastSuccess = Date() }
            return ok
        } catch {
            return false
        }
    }

    /// Invalidate the cached auth — next destructive action prompts again.
    static func invalidateCache() {
        lastSuccess = nil
    }
}
