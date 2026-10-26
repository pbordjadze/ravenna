import CoreGraphics
import Foundation
import Observation
import os
import PaintCore

/// A template and its saved progress, loaded for painting.
nonisolated struct PaintingDocument: Sendable {
    var template: Template
    var progress: PaintProgress
    /// Something the painter should be told once the painting is on screen.
    var notice: OpenNotice? = nil
}

/// What happened to a painting on its way to the screen.
nonisolated enum OpenNotice: Equatable, Sendable {
    /// The saved progress couldn't be used (damaged, or for another template); it starts fresh.
    case progressReset
    /// The template was regenerated from the photo; `keptProgress` if painted areas carried over.
    case regenerated(keptProgress: Bool)
}

/// The user's artworks. Metadata lives in memory (loaded at launch, it is small); templates
/// are loaded on demand. File work runs off the main actor (`Background.run`), serialized per
/// artwork so writes land in the order they were made; only the launch-time scan in `init`
/// runs on it.
@Observable
final class Library {
    /// An artwork still being generated in the background (first-launch samples).
    struct Placeholder: Identifiable, Hashable {
        let sample: Sample
        var id: String { sample.id }
    }

    private(set) var artworks: [Artwork] = []
    private(set) var placeholders: [Placeholder] = []
    /// The most recently deleted artwork, restorable until the undo window closes.
    private(set) var recentlyDeleted: Artwork?
    /// Artworks being regenerated (`regenerate(artwork:settings:)`) and their 0…1 progress.
    private(set) var regenerating: [UUID: Double] = [:]
    /// Artworks whose progress or details didn't reach the disk; cleared by the next
    /// successful save of them.
    private(set) var writeFailures: [UUID: WriteFailure] = [:]

    struct WriteFailure: Equatable {
        var message: String
        var date: Date
    }

    /// Why an artwork can't be opened for painting.
    nonisolated enum OpenError: Error, Equatable {
        /// Written by a newer app (metadata, template or progress); kept untouched.
        case needsNewerApp
        /// The template is unreadable; `canRegenerate` if the photo it came from is available.
        case damaged(canRegenerate: Bool)
        /// A file couldn't be read this time (an I/O or protection error, not damage); nothing
        /// was changed, so opening it again may work.
        case unreadable
    }

    nonisolated enum RegenerationError: Error, Equatable {
        case inProgress
        case saveFailed
    }

    /// Why a painting someone sent (`receive`) couldn't be added.
    nonisolated enum ReceiveError: LocalizedError, Equatable {
        /// Sent from a newer app, in a format this one can't read.
        case needsNewerApp
        /// Not a painting, or a damaged one.
        case damaged
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .needsNewerApp:
                String(localized: "library.receive.needsNewerApp",
                       defaultValue: "This painting was sent from a newer version of Paint by Moonlight. Update the app to open it.",
                       comment: "Alert message when a painting someone sent was made by a newer version of the app")
            case .damaged:
                String(localized: "library.receive.damaged",
                       defaultValue: "This file may be damaged, or it isn’t a painting. Ask whoever sent it to send it again.",
                       comment: "Alert message when a file opened as a painting someone sent can't be read")
            case .saveFailed:
                String(localized: "library.receive.saveFailed",
                       defaultValue: "The painting couldn’t be saved on this device. Free up some space and open it again.",
                       comment: "Alert message when a painting someone sent can't be written to the library")
            }
        }
    }

    @ObservationIgnored let store: ArtworkStore
    /// The create flow's unfinished painting, kept in a folder of the store's root.
    @ObservationIgnored let drafts: Drafts
    @ObservationIgnored private var writes: [UUID: Task<Bool, Never>] = [:]
    @ObservationIgnored private var purge: Task<Void, Never>?
    /// The newest progress submitted per artwork, kept until a write of exactly that
    /// submission succeeds. Retrying saves it, so a retry never puts an older snapshot over
    /// a newer queued one.
    @ObservationIgnored private var unsavedProgress: [UUID: (progress: PaintProgress, token: Int)] = [:]
    /// Artworks whose metadata write failed and hasn't been superseded by a successful one.
    @ObservationIgnored private var unsavedMeta: Set<UUID> = []
    @ObservationIgnored private var nextToken = 0

    /// What a queued write saves, for failure bookkeeping.
    private enum Saves {
        /// Thumbnails, trash: cosmetic or redone later, so failures are only logged.
        case other
        case meta
        case progress(token: Int)
    }

    static let undoWindow: Duration = .seconds(6)
    static let seededKey = "library.seededStarterSamples"
    /// Launches whose seeding produced nothing; seeding is retried until `maxSeedAttempts`.
    static let seedFailuresKey = "library.starterSampleFailures"
    static let maxSeedAttempts = 3

    init(store: ArtworkStore) {
        self.store = store
        drafts = Drafts(store: DraftStore(root: store.root.appending(path: "Drafts", directoryHint: .isDirectory)))
        store.purgeStaging()
        store.purgeTrash()
        artworks = store.loadAll().sorted(by: Self.newestFirst)
    }

    /// The library used by the running app: the real one (Debug builds: or a throwaway one
    /// for demos and the test host, so they never touch real paintings).
    static func forLaunch() -> Library {
        // Shared files left over from earlier runs. The cutoff spares exports started right
        // after launch; the sweep runs off the main actor so it never delays launch.
        let launch = Date.now
        Task { await Background.run { ArtworkExporter.purgeExports(createdBefore: launch) } }
        #if DEBUG
        if DemoMode.isActive || DemoMode.isTestHost {
            let root = FileManager.default.temporaryDirectory.appending(path: "DemoLibrary", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: root)
            let library = Library(store: ArtworkStore(root: root))
            ShellDemo.current?.prepare(library)
            return library
        }
        #endif
        let library = Library(store: ArtworkStore(root: ArtworkStore.defaultRoot))
        library.seedIfNeeded()
        return library
    }

    // MARK: Queries

    /// Painted on and not finished: favorites first, then newest change first.
    var inProgress: [Artwork] { Self.favoritesFirst(artworks.filter { $0.isStarted && !$0.isComplete }) }
    /// Nobody has painted on them yet: in no way in progress. Favorites first, then newest change first.
    var readyToPaint: [Artwork] { Self.favoritesFirst(artworks.filter { !$0.isStarted && !$0.isComplete }) }
    /// Favorites first, then most recently finished first.
    var finished: [Artwork] {
        Self.favoritesFirst(
            artworks.filter(\.isComplete).sorted { ($0.completedAt ?? $0.modifiedAt) > ($1.completedAt ?? $1.modifiedAt) })
    }
    func inProgress(matching query: GalleryQuery) -> [Artwork] { inProgress.filter(query.includes) }
    func readyToPaint(matching query: GalleryQuery) -> [Artwork] { readyToPaint.filter(query.includes) }
    func finished(matching query: GalleryQuery) -> [Artwork] { finished.filter(query.includes) }
    var isEmpty: Bool { artworks.isEmpty && placeholders.isEmpty }
    /// No painting and no draft: the gallery is its empty state, with its own New Painting.
    var isBare: Bool { isEmpty && drafts.current == nil }

    func artwork(with id: UUID) -> Artwork? { artworks.first { $0.id == id } }

    /// The newest failed save of an artwork still in the library (a pending deletion hides it).
    var latestWriteFailure: (artwork: Artwork, failure: WriteFailure)? {
        writeFailures
            .compactMap { entry in artwork(with: entry.key).map { (artwork: $0, failure: entry.value) } }
            .max { $0.failure.date < $1.failure.date }
    }

    // MARK: Creating

    @discardableResult
    func create(_ draft: ArtworkDraft) async throws -> Artwork {
        let artwork = Artwork(
            title: draft.title, createdAt: draft.date, template: draft.template, settings: draft.settings,
            settingsOrigin: draft.settingsOrigin, paintingLength: draft.paintingLength,
            progress: draft.progress, sampleName: draft.sampleName)
        let store = self.store
        try await Background.run {
            let progress = draft.progress ?? PaintProgress(regionCount: draft.template.regions.count)
            let thumbnail = Library.thumbnailPNG(draft.template, painted: progress.painted)
            let source = draft.photo.flatMap {
                ImageCodec.jpegData(ImageCodec.downscaled($0, maxPixelSize: ArtworkStore.sourceMaxPixelSize), quality: 0.88)
            }
            try store.create(
                artwork, template: draft.template, progress: progress, sourceJPEG: source, thumbnailPNG: thumbnail,
                refinements: draft.refinements)
        }
        insert(artwork)
        return artwork
    }

    /// A painting someone sent (`SharedPainting`, a `.moonlight` file) as a new painting, blank and
    /// with its sender's title (else `fallbackTitle`, the file's name), and its colors' nicknames
    /// its own. With the sender's photo (or library picture) it has the photo peek, and a damaged
    /// template is made again from it, without the sender's edits, which never travel; without,
    /// neither. A photo that doesn't decode is left out.
    func receive(_ data: Data, fallbackTitle: String?) async throws -> Artwork {
        let decoded: (SharedPainting, CGImage?)
        do {
            decoded = try await Background.run {
                let shared = try SharedPaintingCodec.decode(data)
                return (shared, shared.photo.flatMap { ImageCodec.image(data: $0, maxPixelSize: ArtworkStore.sourceMaxPixelSize) })
            }
        } catch let error as Template.CodingError where error.requiresNewerReader {
            throw ReceiveError.needsNewerApp
        } catch {
            Log.library.error("A received painting couldn't be read: \(String(describing: error), privacy: .public)")
            throw ReceiveError.damaged
        }
        let (shared, photo) = decoded
        if shared.photo != nil, photo == nil { Log.library.error("A received painting's photo couldn't be decoded") }
        let title = shared.title.isEmpty ? fallbackTitle ?? String(localized: "Painting") : shared.title
        let settings = shared.settings ?? (shared.template.lineArt == nil ? Artwork.settingsBeforeLineArt : GenerationSettings())
        do {
            return try await create(ArtworkDraft(
                title: title, template: shared.template, settings: settings, photo: photo,
                // A library picture's name only beside its photo: alone it could name any picture,
                // which a damaged template would then be made again from.
                sampleName: photo == nil ? nil : shared.sampleName))
        } catch {
            Log.library.error("Saving a received painting failed: \(String(describing: error), privacy: .public)")
            throw ReceiveError.saveFailed
        }
    }

    /// First launch: prepares a couple of ready-to-paint samples in the background (shown
    /// as placeholders meanwhile), so the gallery is never empty on day one.
    @discardableResult
    func seedIfNeeded(_ samples: [Sample] = Sample.starters, defaults: UserDefaults = .standard) -> Task<Void, Never>? {
        guard !defaults.bool(forKey: Self.seededKey) else { return nil }
        guard artworks.isEmpty else {
            defaults.set(true, forKey: Self.seededKey)
            defaults.removeObject(forKey: Self.seedFailuresKey)
            return nil
        }
        // Nothing made (say, the device was out of space): try again on later launches, but not
        // forever. The attempt is counted before seeding, not after: a launch that ends while
        // seeding (the system ending the app for memory) counts too, or it would end every launch.
        let attempt = defaults.integer(forKey: Self.seedFailuresKey) + 1
        guard attempt <= Self.maxSeedAttempts else {
            defaults.set(true, forKey: Self.seededKey)
            defaults.removeObject(forKey: Self.seedFailuresKey)
            return nil
        }
        defaults.set(attempt, forKey: Self.seedFailuresKey)
        return seed(samples.map { SeedItem(sample: $0) }) { created in
            guard created > 0 || attempt >= Self.maxSeedAttempts else { return }
            defaults.set(true, forKey: Self.seededKey)
            defaults.removeObject(forKey: Self.seedFailuresKey)
        }
    }

    #if DEBUG
    /// `gallery-preparing`: `samples` as the first launch's placeholders, held there with nothing
    /// made, for the screenshot of the wait.
    func holdPlaceholders(_ samples: [Sample]) {
        placeholders = samples.map { Placeholder(sample: $0) }
    }
    #endif

    struct SeedItem {
        var sample: Sample
        /// Fraction already painted (demos).
        var painted: Double?
        /// How long ago it was last painted; orders the gallery.
        var age: TimeInterval = 0
        /// Demos use smaller photos so they are ready quickly even in Debug builds.
        var photoMaxPixelSize = ArtworkStore.sourceMaxPixelSize
    }

    /// Generates artworks from bundled samples, one after another, showing placeholders
    /// until each is ready. `completion` gets the number of artworks created.
    ///
    /// At utility priority: nobody waits on a seed (its placeholder shows meanwhile), and the
    /// line-art models and the pipeline take every core, which at the caller's priority starved
    /// the main thread on CI's iPad simulator until UI tests timed out querying the app.
    @discardableResult
    func seed(_ items: [SeedItem], completion: ((_ created: Int) -> Void)? = nil) -> Task<Void, Never> {
        let now = Date.now
        placeholders = items.map { Placeholder(sample: $0.sample) }
        return Task(priority: .utility) {
            var created = 0
            for (index, item) in items.enumerated() {
                // Earlier items sort first when ages tie.
                let date = now.addingTimeInterval(-item.age - Double(index))
                let clock = ContinuousClock.now
                do {
                    let draft = try await ArtworkFactory.draft(
                        sample: item.sample, paintedFraction: item.painted, date: date,
                        photoMaxPixelSize: item.photoMaxPixelSize)
                    try await create(draft)
                    created += 1
                    Log.library.notice("Seeded \(item.sample.id, privacy: .public) in \(String(describing: ContinuousClock.now - clock), privacy: .public)")
                } catch {
                    Log.library.error("Seeding \(item.sample.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
                placeholders.removeAll { $0.id == item.sample.id }
            }
            completion?(created)
        }
    }

    // MARK: Editing

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var artwork = artwork(with: id), !artwork.needsNewerApp, artwork.title != trimmed else { return }
        artwork.title = trimmed
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    func setFavorite(_ id: UUID, _ favorite: Bool) {
        guard var artwork = artwork(with: id), !artwork.needsNewerApp, artwork.isFavorite != favorite else { return }
        artwork.isFavorite = favorite
        replace(artwork, resort: false)
        persistMeta(artwork)
    }

    /// Starts a painting over. False when it can't be: written by a newer app, gone, or its
    /// template can't be read just now; nothing changes then.
    @discardableResult
    func restart(_ id: UUID) async -> Bool {
        guard artwork(with: id)?.needsNewerApp == false else { return false }
        // The fresh progress is sized from the template: metadata can be stale, and progress
        // that doesn't fit would be discarded on the next open with a "couldn't be read" notice.
        _ = await writes[id]?.value
        let store = self.store
        // Nil when damaged: opening offers to regenerate, which sizes progress itself.
        let template: Template?
        do {
            template = try await Background.run { try Library.readTemplate(id, from: store) }
        } catch {
            return false  // written by a newer app, or unreadable just now: nothing changes
        }
        guard var artwork = artwork(with: id), !artwork.needsNewerApp else { return false }
        if let template { artwork.adopt(template, settings: artwork.settings) }
        let fresh = PaintProgress(regionCount: artwork.regionCount)
        artwork.record(fresh)
        replace(artwork)
        persistProgress(fresh, of: artwork)
        await refreshThumbnail(id, template: template, progress: fresh)
        return true
    }

    /// Saves painting progress (called debounced while painting).
    func saveProgress(_ progress: PaintProgress, for id: UUID) {
        guard var artwork = artwork(with: id), !artwork.needsNewerApp else { return }
        guard artwork.regionCount == progress.regionCount else {
            Log.library.error("Not saving progress of \(id.uuidString, privacy: .public): \(progress.regionCount) regions, artwork has \(artwork.regionCount)")
            return
        }
        artwork.record(progress)
        replace(artwork)
        persistProgress(progress, of: artwork)
    }

    /// Saves again what a failed write left unsaved: the newest progress submitted, or else
    /// the details. A new failure shows up again in `writeFailures`.
    func retrySaving(_ id: UUID) {
        clearWriteFailure(id)
        guard let artwork = artwork(with: id) else { return }
        if let unsaved = unsavedProgress[id], unsaved.progress.regionCount == artwork.regionCount {
            persistProgress(unsaved.progress, of: artwork)
        } else if unsavedMeta.contains(id) {
            persistMeta(artwork)
        }
    }

    /// Re-renders the thumbnail, then publishes its new version to the gallery. False when it
    /// didn't reach the disk, so the caller can try again.
    @discardableResult
    func refreshThumbnail(_ id: UUID, template: Template? = nil, progress: PaintProgress) async -> Bool {
        // A painting deleted meanwhile (closing the screen it was deleted from) has no thumbnail to make.
        guard let existing = artwork(with: id), !existing.needsNewerApp else { return false }
        let written = await enqueue(id) { store in
            let t = try template ?? store.readTemplate(id)
            guard let png = Library.thumbnailPNG(t, painted: progress.painted) else { return }
            try store.writeThumbnail(png, for: id)
        }.value
        guard written, var artwork = artwork(with: id) else { return written }
        artwork.thumbnailVersion += 1
        replace(artwork, resort: false)
        persistMeta(artwork)
        return true
    }

    // MARK: Deleting (undoable)

    func delete(_ id: UUID) {
        guard let artwork = artwork(with: id) else { return }
        finalizeDeletion()
        artworks.removeAll { $0.id == id }
        offerUndo(artwork)
        let moved = enqueue(id) { store in try store.moveToTrash(id) }
        Task { [weak self] in
            // The folder never left: the painting is still there, at this launch as at the next.
            guard await !moved.value, let self, self.artwork(with: id) == nil else { return }
            if recentlyDeleted?.id == id {
                purge?.cancel()
                recentlyDeleted = nil
            }
            insert(artwork)
        }
    }

    func undoDelete() {
        guard let artwork = recentlyDeleted else { return }
        purge?.cancel()
        recentlyDeleted = nil
        let id = artwork.id
        // A delete whose move to the trash failed left the folder where it was: nothing to restore.
        let restored = enqueue(id) { store in if store.isInTrash(id) { try store.restoreFromTrash(id) } }
        insert(artwork)
        Task { [weak self] in
            // Still in the trash, which the next launch empties: shown as deleted, with Undo again
            // (a deletion pending meanwhile is made final, as a new delete makes it).
            guard await !restored.value, let self, self.artwork(with: id) != nil else { return }
            artworks.removeAll { $0.id == id }
            finalizeDeletion()
            offerUndo(artwork)
        }
    }

    /// Holds `artwork` for Undo until `undoWindow` has passed.
    private func offerUndo(_ artwork: Artwork) {
        recentlyDeleted = artwork
        purge = Task { [weak self] in
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            self?.finalizeDeletion()
        }
    }

    /// Makes the pending deletion permanent (the undo window closed).
    func finalizeDeletion() {
        guard let artwork = recentlyDeleted else { return }
        purge?.cancel()
        recentlyDeleted = nil
        let id = artwork.id
        clearWriteFailure(id)
        unsavedProgress[id] = nil
        unsavedMeta.remove(id)
        enqueue(id) { store in store.purgeTrash(id) }
    }

    // MARK: Loading

    /// Loads an artwork's template and progress. Throws `OpenError` when it can't be painted;
    /// progress that can't be used is replaced by fresh progress (`OpenNotice.progressReset`,
    /// reported once: the fresh progress is saved) and stale metadata is repaired.
    func loadForPainting(_ id: UUID) async throws -> PaintingDocument {
        guard let artwork = artwork(with: id) else { throw OpenError.damaged(canRegenerate: false) }
        guard !artwork.needsNewerApp else { throw OpenError.needsNewerApp }
        _ = await writes[id]?.value
        let store = self.store
        let (template, saved) = try await Background.run { () throws -> (Template, ArtworkStore.SavedProgress) in
            guard let template = try Library.readTemplate(id, from: store) else {
                throw OpenError.damaged(canRegenerate: ArtworkFactory.canRegenerate(artwork, store: store))
            }
            return (template, try Library.readProgress(id, regionCount: template.regions.count, from: store))
        }

        let reset: Bool
        switch saved.problem {
        case .damaged?, .mismatched?: reset = true
        // A painting that had progress lost its file; say so rather than silently start over.
        case .missing?: reset = artwork.paintedCount > 0
        case nil: reset = false
        }
        // Keep the metadata true to what is on disk (the gallery and saveProgress rely on it),
        // without moving the painting in the gallery's order.
        if let current = self.artwork(with: id) {
            var updated = current
            updated.adopt(template, settings: current.settings)
            if reset || updated.paintedCount != saved.progress.paintedCount {
                updated.record(saved.progress, at: updated.modifiedAt)
            }
            if updated != current {
                replace(updated, resort: false)
                let snapshot = updated, progress = saved.progress
                enqueue(id) { store in
                    if reset { try store.writeProgress(progress, for: id) }
                    try store.writeMeta(snapshot)
                }
            }
        }
        return PaintingDocument(template: template, progress: saved.progress, notice: reset ? .progressReset : nil)
    }

    /// Generates an artwork's template again from its photo (`ArtworkFactory.sourcePhoto`:
    /// `source.jpg`, or the library picture it was made from) with `settings`, off the main
    /// actor, and swaps it in atomically; without either it throws
    /// `ArtworkFactory.FactoryError.sourceUnavailable` and changes nothing. Progress carries
    /// over by painted area when the old template is still readable; otherwise the painting
    /// starts fresh. Recovers damaged paintings (`PaintingRecoveryView`, with the artwork's own
    /// `settings`). `regenerating[id]` reports progress meanwhile.
    func regenerate(artwork id: UUID, settings: GenerationSettings) async throws -> PaintingDocument {
        guard let artwork = artwork(with: id) else { throw ArtworkStore.StoreError.notFound }
        guard !artwork.needsNewerApp else { throw OpenError.needsNewerApp }
        guard regenerating[id] == nil else { throw RegenerationError.inProgress }
        regenerating[id] = 0
        defer { regenerating[id] = nil }
        _ = await writes[id]?.value

        // Called on pipeline threads; hops to the main actor. The last 5 % are for saving.
        let report: @Sendable (Float) -> Void = { value in
            Task { @MainActor in
                guard self.regenerating[id] != nil else { return }
                self.regenerating[id] = 0.95 * Double(value)
            }
        }
        let store = self.store
        let (old, savedProgress, photo, refinements) = try await Background.run {
            () throws -> (Template?, ArtworkStore.SavedProgress, RGBAImage, TemplateRefinements) in
            let old = try Library.readTemplate(id, from: store)
            // Progress from a newer app is never overwritten, even when the template is damaged.
            let saved = try Library.readProgress(id, regionCount: old?.regions.count ?? 0, from: store)
            let refinements: TemplateRefinements
            do {
                refinements = try store.readRefinements(id)
            } catch {
                Log.library.error("Refinements of \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
                throw OpenError.unreadable
            }
            return (old, saved, try ArtworkFactory.sourcePhoto(of: artwork, in: store), refinements)
        }
        let template = try await ArtworkFactory.template(from: photo, settings: settings, refinements: refinements, progress: report)
        let (progress, thumbnail) = await Background.run { () -> (PaintProgress, Data?) in
            let progress = old.map { savedProgress.progress.remapped(from: $0, to: template) }
                ?? PaintProgress(regionCount: template.regions.count)
            return (progress, Library.thumbnailPNG(template, painted: progress.painted))
        }
        try Task.checkCancellation()

        var updated = self.artwork(with: id) ?? artwork
        updated.adopt(template, settings: settings)
        updated.format = Artwork.currentFormat
        updated.record(progress)
        updated.thumbnailVersion += 1
        let snapshot = updated
        let saved = await enqueue(id) { store in
            try store.replaceContents(of: snapshot, template: template, progress: progress, thumbnailPNG: thumbnail)
        }.value
        guard saved else { throw RegenerationError.saveFailed }
        // The new contents include the newest progress and details: nothing older is left to retry.
        unsavedProgress[id] = nil
        unsavedMeta.remove(id)
        clearWriteFailure(id)
        replace(updated)
        return PaintingDocument(template: template, progress: progress, notice: .regenerated(keptProgress: progress.paintedCount > 0))
    }

    /// The photo an artwork was made from (the painting screen's photo peek), decoded off the main actor.
    func sourcePhoto(for id: UUID, maxPixelSize: Int? = nil) async -> CGImage? {
        let store = self.store
        return await Background.run { store.source(id, maxPixelSize: maxPixelSize) }
    }

    /// Waits until every queued write has reached the disk.
    func flush() async {
        for task in Array(writes.values) { _ = await task.value }
    }

    // MARK: Internals

    /// An artwork's template, or nil when it is damaged. A template from a newer app throws
    /// `OpenError.needsNewerApp` and one that can't be read now (an I/O or protection error,
    /// not a missing or corrupt file) `OpenError.unreadable`: both are kept, never replaced.
    private nonisolated static func readTemplate(_ id: UUID, from store: ArtworkStore) throws -> Template? {
        do {
            return try store.readTemplate(id)
        } catch let error as Template.CodingError where error.requiresNewerReader {
            throw OpenError.needsNewerApp
        } catch let error as CocoaError where !Self.isDamage(error) {
            Log.library.error("Template of \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
            throw OpenError.unreadable
        } catch {
            Log.library.error("Template of \(id.uuidString, privacy: .public) is unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// A file that is gone or whose content is bad, as opposed to one that failed to be read.
    nonisolated static func isDamage(_ error: CocoaError) -> Bool {
        switch error.code {
        case .fileNoSuchFile, .fileReadNoSuchFile, .fileReadCorruptFile: true
        default: false
        }
    }

    /// An artwork's saved progress for a template of `regionCount` regions. Progress from a
    /// newer app throws `OpenError.needsNewerApp` and a file that can't be read now
    /// `OpenError.unreadable`: both are kept, never replaced with fresh progress.
    private nonisolated static func readProgress(
        _ id: UUID, regionCount: Int, from store: ArtworkStore
    ) throws -> ArtworkStore.SavedProgress {
        do {
            return try store.readProgress(id, regionCount: regionCount)
        } catch is PaintProgress.CodingError {
            throw OpenError.needsNewerApp
        } catch {
            Log.library.error("Progress of \(id.uuidString, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
            throw OpenError.unreadable
        }
    }

    private nonisolated static func thumbnailPNG(_ template: Template, painted: [Bool]) -> Data? {
        TemplateRasterizer.pngData(template, painted: painted, style: .thumbnail, maxPixelSize: ArtworkStore.thumbnailMaxPixelSize)
    }

    /// A stable partition: each group keeps the order it came in.
    private static func favoritesFirst(_ list: [Artwork]) -> [Artwork] {
        list.filter(\.isFavorite) + list.filter { !$0.isFavorite }
    }

    private static func newestFirst(_ a: Artwork, _ b: Artwork) -> Bool { a.modifiedAt > b.modifiedAt }

    private func insert(_ artwork: Artwork) {
        artworks.removeAll { $0.id == artwork.id }
        artworks.append(artwork)
        artworks.sort(by: Self.newestFirst)
    }

    private func replace(_ artwork: Artwork, resort: Bool = true) {
        guard let index = artworks.firstIndex(where: { $0.id == artwork.id }) else { return }
        artworks[index] = artwork
        if resort { artworks.sort(by: Self.newestFirst) }
    }

    private func persistMeta(_ artwork: Artwork) {
        enqueue(artwork.id, saves: .meta) { store in try store.writeMeta(artwork) }
    }

    /// Writes progress and the details recording it, remembering the progress until it is
    /// on disk.
    private func persistProgress(_ progress: PaintProgress, of artwork: Artwork) {
        let id = artwork.id
        nextToken += 1
        let token = nextToken
        unsavedProgress[id] = (progress, token)
        enqueue(id, saves: .progress(token: token)) { store in
            try store.writeProgress(progress, for: id)
            try store.writeMeta(artwork)
        }
    }

    /// Queues file work for one artwork behind its earlier writes; resolves to success.
    @discardableResult
    private func enqueue(
        _ id: UUID, saves: Saves = .other, _ work: @escaping @Sendable (ArtworkStore) throws -> Void
    ) -> Task<Bool, Never> {
        let previous = writes[id]
        let store = self.store
        let task = Task<Bool, Never> {
            _ = await previous?.value
            do {
                try await Background.run { try work(store) }
                recordWrite(id, saves, error: nil)
                return true
            } catch {
                Log.library.error("Write failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                recordWrite(id, saves, error: error)
                return false
            }
        }
        writes[id] = task
        return task
    }

    private func recordWrite(_ id: UUID, _ saves: Saves, error: (any Error)?) {
        if let error {
            // Nothing to retry for an artwork deleted meanwhile.
            guard artwork(with: id) != nil || recentlyDeleted?.id == id else {
                unsavedProgress[id] = nil
                unsavedMeta.remove(id)
                return
            }
            switch saves {
            case .other: return
            case .meta, .progress: unsavedMeta.insert(id)
            }
            writeFailures[id] = WriteFailure(message: error.localizedDescription, date: .now)
            return
        }
        switch saves {
        case .other: return
        case .meta:
            unsavedMeta.remove(id)
        case .progress(let token):
            if unsavedProgress[id]?.token == token { unsavedProgress[id] = nil }
            // Writes of one artwork land in order, so these details include every earlier change.
            unsavedMeta.remove(id)
        }
        if unsavedProgress[id] == nil, !unsavedMeta.contains(id) { clearWriteFailure(id) }
    }

    /// Only when there is one: every save lands here, and views observe the failures.
    private func clearWriteFailure(_ id: UUID) {
        if writeFailures[id] != nil { writeFailures[id] = nil }
    }
}
