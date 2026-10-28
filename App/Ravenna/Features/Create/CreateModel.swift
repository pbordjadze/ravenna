import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import Observation
import os
import PaintCore
import PhotosUI
import SwiftUI

/// Drives the create flow: holds the chosen photo and the painter's recipe (how many pieces, the
/// eyes, the mouth, the ground and the panel: `MosaicEngine.Recipe`), and lays the
/// mosaic again as the recipe changes: quick drafts at a smaller size while the Pieces slider is
/// dragged (`MosaicMaker.draftLongSide`), the mosaic at its own size once it settles, always
/// discarding stale work.
///
/// Ravenna's seam: Paint by Moonlight's model generated templates from its sliders' settings,
/// chose them for each photo (Suggested settings) and refined them (Refine, drafts); here the
/// engine lays a mosaic (`MosaicMaker`), its template made from it, and of that only a Refine of
/// Ravenna's own remains (`MosaicRefineView`: its marks are the recipe's). A photo's contours and
/// faces are found once for each panel of it (`MosaicMaker.analyze`); the engine's mosaics are
/// kept by the recipe's tiles (`TileKey`), so a ground or a gold mark changes only how the same
/// tiles are laid. A library picture whose recipe a bundled mosaic stands for is laid from it
/// at once. The preview draws the mosaic in the finish the app shows every mosaic in (`MosaicLook`).
@Observable
final class CreateModel {
    struct Source {
        let image: RGBAImage
        /// The photo, whole, at its stored size: what the panel cuts and the engine reads.
        let preview: CGImage
        let sampleName: String?
    }

    nonisolated struct Preview: Sendable, Identifiable {
        let id = UUID()
        /// The mosaic laid (its ground on it).
        let mosaic: Mosaic
        /// Its template: made for the mosaic at its own size only, never for a draft.
        let template: Template?
        let picture: Picture
        /// The recipe it was laid with.
        let recipe: MosaicEngine.Recipe
        /// Laid at the draft's size while a slider moves.
        let isDraft: Bool
    }

    /// What the comparison shows beside the photo: the mosaic, every tile set, as it shows.
    nonisolated enum Picture: Sendable {
        case painting(CGImage)
    }

    nonisolated struct Stats: Equatable, Sendable {
        var colors: Int
        var areas: Int
        var estimate: TimeInterval

        init(_ m: Mosaic) {
            colors = m.palette.count
            areas = m.tiles.count
            estimate = PaintingTime.estimate(regionCount: m.tiles.count + 1)
        }

        var summary: String { TemplateCounts.summary(colors: colors, areas: areas, seconds: estimate) }
    }

    enum Phase: Equatable {
        case idle
        case loading
        /// The photo's contours and faces are being found (for the panel shown).
        case analyzing
        case generating
        case ready
        case failed(String)
    }

    nonisolated enum CreateError: LocalizedError {
        case unreadable, renderFailed, cameraCapture

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "create.error.unreadable", defaultValue: "This photo couldn’t be opened. Try another one.",
                       comment: "Error when a chosen photo can't be decoded")
            case .renderFailed:
                String(localized: "create.error.renderFailed", defaultValue: "The painting couldn’t be made. Try different settings.",
                       comment: "Error when the painting can't be made from the photo")
            case .cameraCapture:
                String(localized: "create.error.cameraCapture",
                       defaultValue: "The photo from the camera couldn’t be used. Try taking it again.",
                       comment: "Error when the photo just taken with the camera can't be used")
            }
        }
    }

    private(set) var source: Source?
    private(set) var preview: Preview?
    /// Of the latest mosaic at its own size.
    private(set) var stats: Stats?
    private(set) var phase: Phase = .idle
    /// The engine's progress on the mosaic at its own size, 0…1.
    private(set) var progress: Double = 0
    private(set) var isAdjusting = false
    /// The recipe the mosaic at its own size is being laid with, while it is.
    private(set) var making: MosaicEngine.Recipe?
    /// The painter's recipe: the card's controls and Refine bind to it, and call `recipeChanged()`.
    var recipe = MosaicEngine.Recipe() {
        didSet {
            // What was drawn in Refine stays on the same part of the photo as the panel changes.
            guard !recipe.marks.isEmpty, PanelKey(oldValue) != PanelKey(recipe), let photo = source?.preview else { return }
            recipe = recipe.reframingMarks(from: oldValue, photoWidth: Double(photo.width), photoHeight: Double(photo.height))
        }
    }
    /// Start Painting was tapped before the mosaic was laid: it starts once it is.
    private(set) var startAsked = false
    /// The name typed for the painting; empty means `defaultTitle`.
    var title = ""
    /// The sample's name, or the date for a photo.
    private(set) var defaultTitle = ""
    /// Identifies the photo the flow is on.
    private(set) var photoID = UUID()

    /// What the painting is called: the typed name, else the default.
    var resolvedTitle: String {
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? defaultTitle : typed
    }

    /// The photo cut to the panel of the mosaic shown (the whole photo before one is): what it is
    /// compared with. Kept, so the comparison is handed the same image while the panel holds.
    private(set) var framed: CGImage?
    @ObservationIgnored private var framedKey: PanelKey?

    /// The panel an analysis is of.
    nonisolated struct PanelKey: Equatable, Sendable {
        let panel: MosaicEngine.Panel
        let centre: SIMD2<Double>

        init(_ recipe: MosaicEngine.Recipe) {
            panel = recipe.panel
            centre = recipe.panel == .whole ? SIMD2(0.5, 0.5) : recipe.centre
        }
    }

    /// The recipe's tiles: what the engine's mosaic depends on (not the ground or the gold marks,
    /// laid on after: `Recipe.forTiles`).
    nonisolated struct TileKey: Equatable, Sendable {
        let recipe: MosaicEngine.Recipe

        init(_ recipe: MosaicEngine.Recipe) {
            self.recipe = recipe.forTiles
        }
    }

    @ObservationIgnored private var analysis: (key: PanelKey, value: MosaicMaker.Analysis)?
    /// The engine's mosaics at their own size, newest first, before their ground: a mosaic is a
    /// megabyte or so.
    @ObservationIgnored private var made: [(key: TileKey, mosaic: Mosaic)] = []
    static let madeKept = 4
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var fullTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var draftPending = false
    @ObservationIgnored private var draftToken = UUID()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var makingID = 0
    /// Bumped by every new photo: work for an earlier one changes nothing.
    @ObservationIgnored private var loadID = 0

    init(recipe: MosaicEngine.Recipe = MosaicEngine.Recipe()) {
        self.recipe = recipe
    }

    /// The photo is being opened, or its contours found: the controls wait.
    var isChoosingSettings: Bool {
        switch phase {
        case .loading, .analyzing: true
        default: false
        }
    }

    /// The preview is the recipe's mosaic at its own size.
    var isFinal: Bool {
        guard let preview else { return false }
        return !preview.isDraft && preview.template != nil && preview.recipe == recipe
    }

    /// Start Painting, asked for early, can go: the mosaic is laid.
    var startsNow: Bool { startAsked && !isChoosingSettings && isFinal }

    /// A tap on Start Painting before the mosaic is laid: it starts once it is
    /// (`TemplatePreviewView`), unless something calls it off first.
    func askForStart() {
        guard source != nil else { return }
        startAsked = true
    }

    /// The start asked for goes, or is not wanted any more.
    func withdrawStart() {
        startAsked = false
    }

    // MARK: Choosing a photo

    func load(sample: Sample) {
        guard let url = sample.url else {
            phase = .failed(CreateError.unreadable.localizedDescription)
            return
        }
        begin(defaultTitle: sample.title, sampleName: sample.id) { try await Self.decode(url: url) }
    }

    func load(item: PhotosPickerItem) {
        begin(defaultTitle: Self.photoTitle(), sampleName: nil) { [self] in
            let data = try await photoData(of: item)
            return try await Self.decode(data: data)
        }
    }

    /// The photos this flow has read from the library, newest first, by the picker's asset
    /// identifier. `PhotoSourceView` resets the inline picker's selection after each pick so the
    /// same photo can be picked again, and the item the picker then gives for a photo it gave
    /// before carries the identifier and no content types: `loadTransferable` answers nil, however
    /// often it is asked (CI, Oct 17: three content types the first time, none the second). The
    /// copy read the first time stands in. The full system picker (Browse All, iPhone's Choose
    /// Photo) is made without a photo library, so its items carry no identifier: nothing is kept.
    @ObservationIgnored private var pickedPhotos: [PickedPhoto] = []

    private struct PickedPhoto {
        let identifier: String
        let data: Data
    }

    /// How many photos `pickedPhotos` keeps: a photo is a few megabytes.
    private static let pickedPhotosKept = 3

    private func photoData(of item: PhotosPickerItem) async throws -> Data {
        let identifier = item.itemIdentifier
        if let data = try await item.loadTransferable(type: Data.self) {
            if let identifier { keepPickedPhoto(data, identifier: identifier) }
            return data
        }
        guard let identifier, let kept = pickedPhotos.first(where: { $0.identifier == identifier }) else {
            throw CreateError.unreadable
        }
        Log.create.notice("The picker had no data for a photo it gave before: using the copy kept from then")
        return kept.data
    }

    private func keepPickedPhoto(_ data: Data, identifier: String) {
        pickedPhotos.removeAll { $0.identifier == identifier }
        pickedPhotos.insert(PickedPhoto(identifier: identifier, data: data), at: 0)
        if pickedPhotos.count > Self.pickedPhotosKept { pickedPhotos.removeLast(pickedPhotos.count - Self.pickedPhotosKept) }
    }

    /// `title` names the painting when the photo came with a name (an opened file); without
    /// one, the date does.
    func load(imageData: Data, title: String? = nil) {
        begin(defaultTitle: title ?? Self.photoTitle(), sampleName: nil) { try await Self.decode(data: imageData) }
    }

    /// A photo that never arrived (the camera's shot couldn't be read): shown in place of the
    /// preview.
    func fail(_ error: CreateError) {
        cancelAll()
        source = nil
        framed = nil
        framedKey = nil
        preview = nil
        stats = nil
        analysis = nil
        made = []
        // A mosaic still being laid belonged to the photo that is gone.
        loadID += 1
        phase = .failed(error.localizedDescription)
    }

    private func begin(defaultTitle: String, sampleName: String?, decode: @escaping () async throws -> Decoded) {
        cancelAll()
        // A new photo gets a new default name, and anything typed for the last one goes; the
        // painter's recipe stays, but for its panel and what was drawn in Refine, which were of
        // the last photo.
        self.defaultTitle = defaultTitle
        title = ""
        photoID = UUID()
        source = nil
        framed = nil
        framedKey = nil
        preview = nil
        stats = nil
        analysis = nil
        made = []
        recipe.marks = []
        recipe.panel = .whole
        recipe.centre = SIMD2(0.5, 0.5)
        progress = 0
        phase = .loading
        loadID += 1
        let load = loadID
        loadTask = Task {
            do {
                let decoded = try await decode()
                try Task.checkCancellation()
                guard load == loadID else { return }
                source = Source(image: decoded.image, preview: decoded.preview, sampleName: sampleName)
                framed = decoded.preview
                framedKey = PanelKey(MosaicEngine.Recipe())
                // The controls wait while its contours and faces are found (the first draft says
                // they are: `generate`), unless a bundled mosaic stands for the recipe.
                phase = MosaicMaker.hasBundled(sampleName, recipe: recipe) ? .ready : .analyzing
                startGeneration(draftFirst: true)
            } catch is CancellationError {
            } catch {
                // A photo given up for another one fails with its own error: it is not news now.
                guard load == loadID else { return }
                Log.create.error("Loading photo failed: \(String(describing: error), privacy: .private)")
                phase = .failed((error as? CreateError ?? .unreadable).localizedDescription)
            }
        }
    }

    // MARK: Adjusting

    /// How long a slider's thumb rests under the finger before the mosaic is laid at its own
    /// size: the painter sees what they get without letting go.
    static let restDelay: Duration = .milliseconds(350)

    /// Call when the painter changed the recipe. While the Pieces slider is held, drafts follow
    /// it; any other change lays the mosaic again, a draft first when the engine must lay it.
    func recipeChanged() {
        guard source != nil, !isChoosingSettings else { return }
        // A start tapped before is for a recipe that is gone.
        startAsked = false
        trace("Recipe changed: pieces \(recipe.pieces), eyes \(recipe.eyes.rawValue), mouth \(recipe.mouth.rawValue), ground \(recipe.ground.rawValue), panel \(recipe.panel.rawValue)")
        if isAdjusting {
            requestDraft()
            scheduleFull(after: Self.restDelay)
        } else {
            startGeneration(draftFirst: true)
        }
    }

    /// A slider drag began or ended. A touch cancels nothing: the first change it makes
    /// (`recipeChanged`) supersedes the mosaic under way, and one that changes none leaves it be.
    func setAdjusting(_ adjusting: Bool) {
        if adjusting { startAsked = false }
        guard adjusting != isAdjusting else { return }
        isAdjusting = adjusting
        trace(adjusting ? "A slider was touched" : "A slider was let go")
        if !adjusting {
            stopDrafts()
            // The resting thumb's mosaic, already under way for this recipe, carries on;
            // otherwise the recipe let go on gets its own, so the painter is never left with a draft.
            if !isFinal, !(isMakingFull && making == recipe) { scheduleFull(after: .milliseconds(60)) }
        }
    }

    /// A mosaic at its own size is under way and not cancelled.
    private var isMakingFull: Bool { making != nil && fullTask?.isCancelled == false }

    /// A line of the app's log with the state the work is in.
    private func trace(_ event: String) {
        let phaseName = String(describing: self.phase)
        Log.create.notice(
            "\(event, privacy: .public) [adjusting \(self.isAdjusting, privacy: .public), full under way \(self.making != nil, privacy: .public), final \(self.isFinal, privacy: .public), phase \(phaseName, privacy: .public)]"
        )
    }

    func cancelAll() {
        loadTask?.cancel()
        fullTask?.cancel()
        stopDrafts()
        startAsked = false
    }

    /// Waits until the work this model started has ended, cancelled work too.
    func settled() async {
        var waited = Set<Task<Void, Never>>()
        while let task = [loadTask, fullTask, draftTask].compactMap({ $0 }).first(where: { !waited.contains($0) }) {
            waited.insert(task)
            await task.value
        }
    }

    /// The painting of the recipe's mosaic at its own size, laying it if needed.
    func makeDraft() async throws -> ArtworkDraft {
        startAsked = false
        _ = await loadTask?.value
        guard let source else { throw CreateError.unreadable }
        let recipe = self.recipe
        if !isFinal {
            fullTask?.cancel()
            stopDrafts()
            await generate(draft: false, recipe: recipe)
        }
        guard let preview, let template = preview.template, !preview.isDraft, preview.recipe == recipe else {
            throw CreateError.renderFailed
        }
        return ArtworkDraft(
            title: resolvedTitle, template: template, settings: GenerationSettings(),
            photo: MosaicMaker.framed(source.preview, panel: recipe.panel, centre: recipe.centre),
            sampleName: source.sampleName, mosaic: preview.mosaic, recipe: recipe)
    }

    /// What the making-of show of `draft` (the painting Start saved) is made from: its mosaic, the
    /// finish the app shows it in, the photo it was laid from and the model's card. None without a mosaic.
    func makingOfSource(for draft: ArtworkDraft) -> MakingOfSource? {
        guard let mosaic = draft.mosaic, let photo = draft.photo else { return nil }
        let sample = draft.sampleName.flatMap(Sample.named), look = MosaicLook.current
        return MakingOfSource(
            mosaic: mosaic, photo: photo, finish: look.finish, title: draft.title,
            credit: sample.map(MakingOfSource.credit(of:)) ?? MakingOfSource.ownPhotoCredit)
    }

    /// Lays the recipe as the cancellable job at its own size, so changes supersede it; a quick
    /// draft first makes something appear at once (not for a bundled mosaic, which is there).
    private func startGeneration(draftFirst: Bool) {
        fullTask?.cancel()
        stopDrafts()
        let recipe = self.recipe
        let bundled = MosaicMaker.hasBundled(source?.sampleName, recipe: recipe)
        fullTask = Task {
            if draftFirst, !bundled, !made.contains(where: { $0.key == TileKey(recipe) }) {
                await generate(draft: true, recipe: recipe)
                guard !Task.isCancelled else { return }
            }
            await generate(draft: false, recipe: recipe)
        }
    }

    private func requestDraft() {
        fullTask?.cancel()
        // A mosaic the thumb's rest started gives way to the drafts again.
        if making != nil, phase == .generating, preview != nil { phase = .ready }
        draftPending = true
        guard draftTask == nil else { return }
        let token = UUID()
        draftToken = token
        // Coalesce: while a draft is laid, further changes only mark it dirty, so the preview
        // keeps up with the finger at the engine's own pace.
        draftTask = Task {
            while draftPending && !Task.isCancelled {
                draftPending = false
                await generate(draft: true, recipe: recipe)
            }
            if draftToken == token { draftTask = nil }
        }
    }

    private func stopDrafts() {
        draftTask?.cancel()
        draftTask = nil
        draftPending = false
        draftToken = UUID()
    }

    private func scheduleFull(after delay: Duration) {
        fullTask?.cancel()
        fullTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await generate(draft: false, recipe: recipe)
        }
    }

    // MARK: Generation

    private func generate(draft: Bool, recipe: MosaicEngine.Recipe) async {
        guard let source else { return }
        if isFinal && preview?.recipe == recipe {
            phase = .ready
            return
        }
        generation += 1
        let id = generation
        let load = loadID
        let kind = draft ? "Draft" : "Full"
        trace("\(kind) #\(id) started")
        if !draft {
            phase = .generating
            progress = 0
            making = recipe
            makingID = id
        }
        defer { if !draft, makingID == id { making = nil } }
        // Called on the engine's threads; hops to the main actor. Only the full size reports.
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                guard self.makingID == id else { return }
                self.progress = value
            }
        }
        do {
            let photo = source.preview, sample = source.sampleName
            let earlier = draft ? nil : made.first(where: { $0.key == TileKey(recipe) })?.mosaic
            var analysis: MosaicMaker.Analysis?
            if earlier == nil, !MosaicMaker.hasBundled(sample, recipe: recipe) {
                analysis = try await analysisOf(recipe, photo: photo, load: load)
            }
            try Task.checkCancellation()
            let shown = try await Self.render(
                photo, analysis: analysis, recipe: recipe, sample: sample, earlier: earlier, look: MosaicLook.current,
                isDraft: draft, progress: draft ? nil : report)
            // Kept even if cancelled meanwhile: it is what this recipe makes of this photo.
            if !draft, load == loadID, let raw = shown.raw { remember(raw, key: TileKey(recipe)) }
            try Task.checkCancellation()
            guard load == loadID else { return }
            // A draft finishing after a newer job began would replace it with less, and one after
            // the recipe's own mosaic is shown would take it back.
            if draft, generation != id || isFinal {
                trace("Draft #\(id) dropped")
                return
            }
            // Drafts follow the finger as they come: a crossfade would blur one into the next.
            withAnimation(draft ? nil : .easeInOut(duration: 0.35)) {
                preview = shown.preview
                if !draft { stats = Stats(shown.preview.mosaic) }
                // The photo beside it is cut as it was.
                if framedKey != PanelKey(recipe) {
                    framedKey = PanelKey(recipe)
                    framed = MosaicMaker.framed(photo, panel: recipe.panel, centre: recipe.centre)
                }
            }
            trace("\(kind) #\(id) shown")
            if draft {
                if generation == id, !isMakingFull { phase = .ready }
            } else if makingID == id {
                phase = .ready
            }
        } catch is CancellationError {
            trace("\(kind) #\(id) cancelled")
        } catch {
            Log.create.error("Laying the mosaic failed: \(String(describing: error), privacy: .public)")
            // No mosaic is on its way: a Start waiting for it would wait for ever.
            startAsked = false
            phase = .failed(CreateError.renderFailed.localizedDescription)
        }
    }

    /// The contours and faces of the recipe's panel of `photo`, found once a panel.
    private func analysisOf(_ recipe: MosaicEngine.Recipe, photo: CGImage, load: Int) async throws -> MosaicMaker.Analysis {
        let key = PanelKey(recipe)
        if let analysis, analysis.key == key { return analysis.value }
        // Another panel: the status says the mosaic is being laid meanwhile.
        if phase == .ready {
            phase = .generating
            progress = 0
        }
        let found = try await MosaicMaker.analyze(MosaicMaker.framed(photo, panel: recipe.panel, centre: recipe.centre))
        if load == loadID { analysis = (key, found) }
        return found
    }

    /// Keeps an engine's mosaic at its own size for coming back to its recipe's tiles.
    private func remember(_ mosaic: Mosaic, key: TileKey) {
        made.removeAll { $0.key == key }
        made.insert((key, mosaic), at: 0)
        if made.count > Self.madeKept { made.removeLast(made.count - Self.madeKept) }
    }

    // MARK: Background work

    /// A decoded photo the engine can work with: at least 16 px on each side, with its image.
    nonisolated struct Decoded: Sendable {
        let image: RGBAImage
        let preview: CGImage

        init(_ image: RGBAImage) throws {
            guard image.width >= 16, image.height >= 16, let preview = PhotoLoader.cgImage(from: image) else {
                throw CreateError.unreadable
            }
            self.image = image
            self.preview = preview
        }
    }

    @concurrent
    static func decode(url: URL) async throws -> Decoded {
        try Decoded(PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    @concurrent
    private static func decode(data: Data) async throws -> Decoded {
        try Decoded(PhotoLoader.load(data: data, maxPixelSize: ArtworkStore.sourceMaxPixelSize))
    }

    /// A preview, and the engine's mosaic before its ground when the engine laid it at its own size.
    nonisolated struct Shown: Sendable {
        var preview: Preview
        var raw: Mosaic?
    }

    /// The recipe's mosaic of `photo`: `earlier` (the engine's, laid before for these tiles) with
    /// its ground, a bundled mosaic, or the engine's from `analysis` at the recipe's size or a
    /// draft's, its ground laid on; its template unless a draft; drawn in `look`'s finish.
    @concurrent
    private static func render(
        _ photo: CGImage, analysis: MosaicMaker.Analysis?, recipe: MosaicEngine.Recipe, sample: String?, earlier: Mosaic?,
        look: MosaicLook, isDraft: Bool, progress: (@Sendable (Double) -> Void)?
    ) async throws -> Shown {
        let laid: Mosaic, raw: Mosaic?
        if let earlier {
            laid = recipe.laid(earlier)
            raw = earlier
        } else if let bundled = MosaicMaker.bundled(sample, recipe: recipe) {
            laid = bundled
            raw = nil
        } else {
            guard let analysis else { throw CreateError.renderFailed }
            let framed = MosaicMaker.framed(photo, panel: recipe.panel, centre: recipe.centre)
            let side = isDraft ? min(MosaicMaker.draftLongSide, recipe.longSide) : recipe.longSide
            let mosaic = try MosaicMaker.make(framed, analysis: analysis, recipe: recipe, side: side, progress: { progress?($0) })
            laid = recipe.laid(mosaic)
            raw = isDraft ? nil : mosaic
        }
        try Task.checkCancellation()
        let template = isDraft ? nil : try MosaicMaker.template(of: laid)
        #if DEBUG
        // Debug builds (CI's simulator runs) check every template's invariants, legible numbers
        // included, and say so in the log (`MosaicCore`'s tests on Linux are where they are kept).
        if let template {
            let report = template.validate(minLabelRadius: LabelSizing.minimumRadius)
            if !report.isValid { Log.create.fault("The mosaic's template violates its invariants: \(String(describing: report), privacy: .public)") }
        }
        #endif
        try Task.checkCancellation()
        guard let image = MosaicPicture.image(laid, finish: look.finish, longest: isDraft ? 1024 : 2048) else {
            throw CreateError.renderFailed
        }
        return Shown(
            preview: Preview(mosaic: laid, template: template, picture: .painting(image), recipe: recipe, isDraft: isDraft),
            raw: raw)
    }

    private static func photoTitle() -> String {
        Date.now.formatted(.dateTime.month(.wide).day())
    }
}
