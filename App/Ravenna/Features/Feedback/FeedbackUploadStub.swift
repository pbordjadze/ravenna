#if DEBUG
import Foundation
import os

/// Debug builds' stand-in for the relay, so no test or CI run ever sends feedback anywhere.
/// The launch argument `-feedback-upload` picks the uploader of a Debug launch:
///
/// - none (the default): a stub that takes the feedback and succeeds, after a moment;
/// - `fail`: a stub that always fails, for the alert that offers Try Again, Share Instead and
///   Cancel;
/// - `fail-once`: a stub that fails the first time of the launch and succeeds after, for Try Again;
/// - `live`: the real uploader (`FeedbackUploader.live`), for trying the relay by hand.
///
/// Debug builds only: Release has neither this type nor the argument (`ci/check_release.sh`).
nonisolated enum FeedbackUploadStub {
    static func choose(argument: String?) -> FeedbackUploader {
        switch argument ?? "" {
        case "live": return .live()
        case "fail": return stub(named: "stub-failing") { _ in true }
        case "fail-once": return stub(named: "stub-failing-once") { attempt in attempt == 1 }
        default: return stub(named: "stub") { _ in false }
        }
    }

    /// The attempts the launch has made, whichever stub made them: the sheet asks for its
    /// uploader again whenever its screen redraws, so a count of its own would start over.
    private static let attempts = OSAllocatedUnfairLock(initialState: 0)

    private static func stub(named name: String, fails: @escaping @Sendable (Int) -> Bool) -> FeedbackUploader {
        FeedbackUploader(name: name) { _, _ in
            let attempt = FeedbackUploadStub.attempts.withLock { count in
                count += 1
                return count
            }
            try await Task.sleep(for: .milliseconds(300))
            if fails(attempt) { throw URLError(.notConnectedToInternet) }
        }
    }
}
#endif
