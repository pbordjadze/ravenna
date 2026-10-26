import Foundation
import PaintCore

/// Persists a painting session: progress about a second after the last change (right
/// away when the painting is finished, and at the latest `maxWait` after the first unsaved
/// change, so continuous painting still saves), and a fresh thumbnail when leaving.
final class PaintingAutosaver {
    let session: PaintingSession
    let artworkID: UUID
    private let library: Library
    private let delay: Duration
    private let maxWait: Duration
    private var pending: Task<Void, Never>?
    /// When the oldest change not yet handed to the library happened.
    private var firstUnsaved: ContinuousClock.Instant?
    private var savedRevision: Int
    /// The revision whose thumbnail is on disk (or at least queued and not known to have failed).
    private var thumbnailRevision: Int
    private var renderingRevision: Int?
    /// The thumbnail render in flight, for tests to wait on.
    private(set) var thumbnailTask: Task<Void, Never>?

    init(
        session: PaintingSession, artworkID: UUID, library: Library,
        delay: Duration = .seconds(1), maxWait: Duration = .seconds(10)
    ) {
        self.session = session
        self.artworkID = artworkID
        self.library = library
        self.delay = delay
        self.maxWait = maxWait
        savedRevision = session.revision
        thumbnailRevision = session.revision
    }

    func sessionChanged() {
        pending?.cancel()
        if session.isComplete {
            saveNow(refreshThumbnail: true)
            return
        }
        let now = ContinuousClock.now
        let first = firstUnsaved ?? now
        firstUnsaved = first
        // Fills that never pause for `delay` would otherwise postpone every save.
        if now - first >= maxWait {
            saveNow()
            return
        }
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow(refreshThumbnail: Bool = false) {
        pending?.cancel()
        pending = nil
        firstUnsaved = nil
        if session.revision != savedRevision {
            savedRevision = session.revision
            library.saveProgress(session.progress, for: artworkID)
        }
        if refreshThumbnail && session.revision != thumbnailRevision && session.revision != renderingRevision {
            let revision = session.revision
            renderingRevision = revision
            let library = library, id = artworkID, template = session.template, progress = session.progress
            thumbnailTask = Task { [weak self] in
                let written = await library.refreshThumbnail(id, template: template, progress: progress)
                self?.thumbnailFinished(revision, written: written)
            }
        }
    }

    /// A failed render is retried by the next `saveNow(refreshThumbnail:)` at this revision.
    private func thumbnailFinished(_ revision: Int, written: Bool) {
        renderingRevision = nil
        if written { thumbnailRevision = revision }
    }
}
