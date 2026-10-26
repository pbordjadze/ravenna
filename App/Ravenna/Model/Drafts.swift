import CoreGraphics
import Foundation
import Observation
import os
import PaintCore

/// Keeps the create flow's draft (`CreateDraft`) on disk: the one unfinished new painting the
/// painter refined, which the gallery offers to continue in builds with Refine (not the release,
/// for now: `init`). The create flow hands it every
/// change (`keep`), written about a second after the last one and at once when the flow closes
/// or the scene leaves the foreground (`saveNow`); starting the painting (`drop`) or the
/// painter's Discard removes it. File work runs off the main actor, one job after another, so
/// writes land in the order they were made.
///
/// A flow keeps a draft only once it has refinements, and never removes another photo's: a new
/// painting replaces the draft when its photo is refined, and not before. A damaged draft is
/// no draft: it is logged and removed. A write that fails keeps its draft waiting, written again by
/// the next save, the painter's Retry (`retry`) or the flow's close, and the flow says so
/// (`saveFailed`), as a painting's progress does (`Library.writeFailures`). A newer draft handed
/// over meanwhile takes its place.
@Observable
final class Drafts {
    /// The draft as it is on disk (what the gallery lists): nil when there is none, or its
    /// file hasn't landed yet.
    private(set) var current: CreateDraft?
    /// The photo whose draft's last write failed, so its latest draft isn't on disk: cleared once
    /// a save lands, the painter retries, or the draft is let go.
    private(set) var saveFailed: UUID?

    /// A draft read back, with its photo, ready for the create flow.
    nonisolated struct Opened: Sendable {
        let draft: CreateDraft
        let photo: Data
        /// The trail its edits made, when the draft kept it (`DraftStore.KeptFile`).
        var kept: EditTrail.Kept?
    }

    @ObservationIgnored let store: DraftStore
    @ObservationIgnored private var pending: (draft: CreateDraft, photo: CGImage, kept: EditTrail.Kept?)?
    /// Whether the draft on disk has the trail its edits made beside it.
    @ObservationIgnored private var keptOnDisk = false
    /// Counts the drops of each photo's draft and the discards, so a write that fails after its
    /// draft was let go doesn't bring it back.
    @ObservationIgnored private var drops: [UUID: Int] = [:]
    @ObservationIgnored private var discards = 0
    /// Counts the drafts handed over (`keep`), so a write that fails puts its draft back only when
    /// none newer came since.
    @ObservationIgnored private var keeps = 0
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var tail: Task<Void, Never>?

    static let delay: Duration = .seconds(1)

    /// Reads the draft on disk, the launch-time scan of the drafts (builds with Refine).
    init(store: DraftStore) {
        self.store = store
        store.purgeStaging()
        // A draft is Refine's, which the release leaves out for now (SideStore and Debug builds
        // have it): the release reads none and leaves the one on disk for a build with Refine.
        #if UNRELEASED
        do {
            current = try store.read()
            keptOnDisk = current != nil && store.hasKept
        } catch let error as CocoaError where !Library.isDamage(error) {
            // Can't be read just now (an I/O or data protection error), which says nothing
            // about the draft: kept for a later launch, as the library keeps such a painting.
            Log.create.error("The draft can't be read now: \(String(describing: error), privacy: .public)")
        } catch {
            Log.create.error("Removing a damaged draft: \(String(describing: error), privacy: .public)")
            store.remove()
        }
        #endif
    }

    /// Takes the flow's latest draft, and the trail its edits made when they have been laid; it
    /// is written once the flow has been quiet for `delay`.
    func keep(_ draft: CreateDraft, photo: CGImage, kept: EditTrail.Kept? = nil) {
        pending = (draft, photo, kept?.edits == draft.refinements.edits ? kept : nil)
        keeps += 1
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes what `keep` was last given without waiting.
    func saveNow() {
        debounce?.cancel()
        debounce = nil
        guard let (draft, photo, kept) = pending else { return }
        pending = nil
        let handedOver = (drops[draft.photoID], discards, keeps)
        enqueue { [self] in
            // Judged here, behind the writes before it: a draft that came back to what is on
            // disk needs none (unless the trail its edits made has been laid since), and the
            // photo is encoded once, with its first draft.
            guard draft != current || (kept != nil && !keptOnDisk) else {
                saveFailed = nil
                return
            }
            let reusesPhoto = current?.photoID == draft.photoID
            let store = store
            do {
                keptOnDisk = try await Background.run { try store.write(draft, photo: reusesPhoto ? nil : photo, kept: kept) }
                current = draft
                saveFailed = nil
            } catch {
                Log.create.error("Saving the draft failed: \(String(describing: error), privacy: .public)")
                // The write leaves the disk as it was (`DraftStore.write`). The draft waits for
                // the next save, unless it was let go meanwhile or a newer one was handed over
                // (waiting or already queued behind this write).
                guard handedOver == (drops[draft.photoID], discards, keeps) else { return }
                pending = (draft, photo, kept)
                saveFailed = draft.photoID
            }
        }
    }

    /// The painter's Retry after a failed write: writes the waiting draft now. A new failure
    /// shows up again in `saveFailed`.
    func retry() {
        saveFailed = nil
        saveNow()
    }

    /// The flow no longer has refinements to keep (they were all undone) or started the painting:
    /// removes the draft if it is this photo's, and any write still waiting for it.
    func drop(photoID: UUID) {
        if pending?.draft.photoID == photoID { forgetPending() }
        drops[photoID, default: 0] += 1
        if saveFailed == photoID { saveFailed = nil }
        enqueue { [self] in
            guard current?.photoID == photoID else { return }
            await removeStored()
        }
    }

    /// The painter's Discard.
    func discard() {
        forgetPending()
        discards += 1
        saveFailed = nil
        enqueue { [self] in await removeStored() }
    }

    /// The draft and its photo as they are on disk, once the writes before are done. Nil when
    /// there is no draft, or it can't be read: a damaged one is removed, one that can't be read
    /// just now (an I/O or data protection error) is kept, as at launch.
    func open() async -> Opened? {
        await flush()
        guard current != nil else { return nil }
        let store = store
        do {
            let opened = try await Background.run { () throws -> Opened in
                guard let draft = try store.read() else { throw DraftStore.StoreError.missingPhoto }
                return Opened(draft: draft, photo: try store.photoData(), kept: store.kept(edits: draft.refinements.edits))
            }
            // A trail on disk that can't be taken up is written again once the edits are laid.
            if opened.kept == nil { keptOnDisk = false }
            return opened
        } catch let error as CocoaError where !Library.isDamage(error) {
            Log.create.error("The draft can't be opened now: \(String(describing: error), privacy: .public)")
            return nil
        } catch {
            Log.create.error("Removing a draft that can't be opened: \(String(describing: error), privacy: .public)")
            discard()
            await flush()
            return nil
        }
    }

    /// Writes what is pending now and waits until every write and removal asked for so far is done.
    func flush() async {
        saveNow()
        _ = await tail?.value
    }

    private func forgetPending() {
        pending = nil
        debounce?.cancel()
        debounce = nil
    }

    private func removeStored() async {
        let store = store
        await Background.run { store.remove() }
        current = nil
        keptOnDisk = false
    }

    /// Queues file work behind the earlier jobs.
    private func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            _ = await previous?.value
            await work()
        }
    }
}
