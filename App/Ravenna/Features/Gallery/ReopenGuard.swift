import Foundation

/// Keeps a painting that can't be opened from locking the app out of its gallery. The shell
/// reopens the painting that was open when the app was last suspended (`AppShellView`), so a
/// painting whose opening crashes would crash every launch. `begin()` marks a reopen as under way
/// and `settled()` clears the mark once the painting has been on screen a while; a launch that
/// finds the mark still set skips the reopen (`mayReopen()`) and shows the gallery instead.
struct ReopenGuard {
    static let key = "shell.reopeningArtwork"
    /// How long a reopened painting stays on screen before its reopen counts as safe.
    static let settleDelay: Duration = .seconds(10)

    var defaults: UserDefaults = .standard

    /// Whether this launch may reopen the last painting: false, once, after a launch whose
    /// reopen never settled.
    func mayReopen() -> Bool {
        guard defaults.bool(forKey: Self.key) else { return true }
        defaults.removeObject(forKey: Self.key)
        return false
    }

    func begin() { defaults.set(true, forKey: Self.key) }

    func settled() { defaults.removeObject(forKey: Self.key) }
}
