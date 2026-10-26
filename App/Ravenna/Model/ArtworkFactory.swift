import CoreGraphics
import Foundation
import PaintCore
import os

/// Turns photos into ready-to-save artwork drafts, off the main actor.
nonisolated enum ArtworkFactory {
    enum FactoryError: Error, Equatable {
        case missingSample
        /// Neither the stored photo nor the library picture an artwork was made from is available.
        case sourceUnavailable
    }

    @concurrent
    static func draft(
        sample: Sample, settings: GenerationSettings = GenerationSettings(),
        paintedFraction: Double? = nil, date: Date = .now,
        photoMaxPixelSize: Int = ArtworkStore.sourceMaxPixelSize
    ) async throws -> ArtworkDraft {
        guard let url = sample.url else { throw FactoryError.missingSample }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: photoMaxPixelSize)
        let image = PhotoLoader.cgImage(from: photo)
        #if DEBUG
        let cached = DemoTemplateCache.url(sample: sample.id, photoMaxPixelSize: photoMaxPixelSize, settings: settings)
        let template: Template
        if let cached, let kept = DemoTemplateCache.template(at: cached) {
            template = kept
        } else {
            template = try await self.template(from: photo, image: image, settings: settings, progress: nil)
            if let cached { DemoTemplateCache.store(template, at: cached) }
        }
        #else
        let template = try await self.template(from: photo, image: image, settings: settings, progress: nil)
        #endif
        var progress: PaintProgress?
        if let paintedFraction {
            var painted = self.progress(painting: paintedFraction, of: template)
            // Plausible painting time for a demo in progress.
            painted.activeSeconds = Double(painted.paintedCount) * 3
            progress = painted
        }
        return ArtworkDraft(
            title: sample.title, template: template, settings: settings, photo: image,
            sampleName: sample.id, progress: progress, date: date)
    }

    /// The template of `photo`, generated the way the create flow does it: subject importance
    /// from Vision (when available) guides colors and detail, and line art (the coloring book by
    /// default) draws from the photo's `LineArtInputs`: the drawing, the contours, the eyes and
    /// the subjects. The painter's `refinements` come with it: the generator's inputs shape the
    /// template (a blank start makes none: `blank`), and the edits are laid on it in order
    /// (`laying`). Polls task cancellation.
    @concurrent
    static func template(
        from photo: RGBAImage, settings: GenerationSettings, refinements: TemplateRefinements = TemplateRefinements(),
        progress: (@Sendable (Float) -> Void)?
    ) async throws -> Template {
        try await template(
            from: photo, image: PhotoLoader.cgImage(from: photo), settings: settings, refinements: refinements, progress: progress)
    }

    @concurrent
    private static func template(
        from photo: RGBAImage, image: CGImage?, settings: GenerationSettings,
        refinements: TemplateRefinements = TemplateRefinements(), progress: (@Sendable (Float) -> Void)?
    ) async throws -> Template {
        // The photo as one area needs neither Vision nor the line-art models.
        if refinements.start == .blank {
            return try laying(refinements.edits, on: blank(from: photo, settings: settings))
        }
        // Side by side, so the line art's eyes and subjects share importance's pass of Vision
        // (`SubjectVision`).
        async let importance = Self.importance(of: image)
        // Computed for this one template: the photo needn't take a place in the cache.
        let lineArt = try await LineArtInputs.forGeneration(of: image, settings: settings.lineArt, cached: false)
        let inputs = refinements.refining(
            importance: await importance, lineArt: lineArt, aspect: Float(photo.width) / Float(max(photo.height, 1)))
        let base = try TemplateGenerator(settings: settings)
            .generate(from: photo, importance: inputs.importance, lineArt: inputs.lineArt, cancel: .task, progress: progress)
            .template
        return try laying(refinements.edits, on: base)
    }

    private static func importance(of image: CGImage?) async -> PaintCore.Grid<Float>? {
        guard let image else { return nil }
        return await SubjectImportance.map(for: image)
    }

    /// The base of a blank start (`TemplateRefinements.Start.blank`): `photo`, the image the
    /// generator would read, as one area (`TemplateEditor.blank`) on the canvas the generator
    /// would make of it for `settings` (`GenerationSettings.workingSize`), in its color space. A
    /// canvas the editor can't take throws, as a failed generation does.
    static func blank(from photo: RGBAImage, settings: GenerationSettings) throws -> Template {
        let size = settings.workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        return try TemplateEditor.blank(width: size.width, height: size.height, photo: photo, colorSpace: photo.colorSpace)
    }

    /// `base` with the painter's edits laid on it, in order, exactly as the create flow shows
    /// them (`EditTrail`): the same base and edits give the same template. An edit that doesn't
    /// fit the base is left out (and logged), as it is on screen.
    static func laying(_ edits: [TemplateEditor.Edit], on base: Template) throws -> Template {
        guard !edits.isEmpty else { return base }
        var trail = EditTrail(base: base)
        let replay = try trail.move(to: edits, cancel: .task)
        if replay.left > 0 { Log.library.info("\(replay.left) of the painting's edits no longer fit it") }
        return trail.template
    }

    /// The photo an artwork was made from, as the create flow loaded it: the stored
    /// `source.jpg`, else the library picture it came from while the library still offers it
    /// (`Sample.named`).
    static func sourcePhoto(of artwork: Artwork, in store: ArtworkStore) throws -> RGBAImage {
        if store.hasSource(artwork.id) {
            return try PhotoLoader.load(url: store.url(.source, of: artwork.id), maxPixelSize: ArtworkStore.sourceMaxPixelSize)
        }
        guard let url = sampleURL(of: artwork) else { throw FactoryError.sourceUnavailable }
        return try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize)
    }

    /// Whether `sourcePhoto(of:in:)` has a photo to regenerate the artwork from.
    static func canRegenerate(_ artwork: Artwork, store: ArtworkStore) -> Bool {
        store.hasSource(artwork.id) || sampleURL(of: artwork) != nil
    }

    private static func sampleURL(of artwork: Artwork) -> URL? {
        artwork.sampleName.flatMap(Sample.named)?.url
    }

    /// Progress with `fraction` of the regions painted the way people paint: color by
    /// color, in palette order.
    static func progress(painting fraction: Double, of t: Template) -> PaintProgress {
        var progress = PaintProgress(regionCount: t.regions.count)
        let target = Int((Double(t.regions.count) * min(max(fraction, 0), 1)).rounded())
        var byColor = [[Int]](repeating: [], count: t.palette.count)
        for (index, region) in t.regions.enumerated() { byColor[Int(region.colorIndex)].append(index) }
        outer: for regions in byColor {
            for region in regions {
                if progress.paintedCount >= target { break outer }
                progress.paint(region)
            }
        }
        return progress
    }
}
