import UIKit

/// Keeps the app running while the writes it queues on leaving the foreground reach the disk:
/// iOS suspends a backgrounded app within seconds, and a write it cut off (a draft's photo, a
/// painting's progress) would lose the last changes. One background task covers every save
/// under way and ends when the last finishes, or when the system's time runs out.
final class BackgroundSaving {
    static let shared = BackgroundSaving()

    private var task = UIBackgroundTaskIdentifier.invalid
    private var running = 0

    /// Whether a background task is held (tests).
    var isHolding: Bool { task != .invalid }

    /// Holds the background task until `work` (a flush of what was just queued) returns.
    func hold(until work: @escaping @MainActor () async -> Void) {
        if task == .invalid {
            task = UIApplication.shared.beginBackgroundTask(withName: "Saving") { [weak self] in
                self?.end()
            }
        }
        running += 1
        Task {
            await work()
            running -= 1
            if running == 0 { end() }
        }
    }

    private func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
