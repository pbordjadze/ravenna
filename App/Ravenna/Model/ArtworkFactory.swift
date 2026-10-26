import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import PaintCore
import os

/// Turns photos into ready-to-save artwork drafts, off the main actor.
///
/// Ravenna's seam: templates are mosaics, made by Ravenna's engine (`MosaicMaker`) from the photo
/// and the painter's recipe, where Paint by Moonlight's generator made them from its settings and
/// refinements.
nonisolated enum ArtworkFactory {
    enum FactoryError: Error, Equatable {
        case missingSample
        /// Neither the stored photo nor the library picture an artwork was made from is available.
        case sourceUnavailable
    }

    /// A painting of a library picture, as the create flow makes it with `recipe`.
    @concurrent
    static func draft(
        sample: Sample, recipe: MosaicEngine.Recipe = MosaicEngine.Recipe(),
        paintedFraction: Double? = nil, date: Date = .now,
        photoMaxPixelSize: Int = ArtworkStore.sourceMaxPixelSize
    ) async throws -> ArtworkDraft {
        guard let url = sample.url else { throw FactoryError.missingSample }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: photoMaxPixelSize)
        guard let image = PhotoLoader.cgImage(from: photo) else { throw FactoryError.missingSample }
        let made = try await self.made(from: image, recipe: recipe, sampleName: sample.id, progress: nil)
        var progress: PaintProgress?
        if let paintedFraction {
            var painted = self.progress(painting: paintedFraction, of: made.template)
            // Plausible painting time for a demo in progress.
            painted.activeSeconds = Double(painted.paintedCount) * 3
            progress = painted
        }
        return ArtworkDraft(
            title: sample.title, template: made.template, settings: GenerationSettings(),
            photo: MosaicMaker.framed(image, panel: recipe.panel, centre: recipe.centre),
            sampleName: sample.id, progress: progress, date: date, mosaic: made.mosaic, recipe: recipe)
    }

    /// The mosaic of `photo` (the whole photo, which the recipe's panel cuts) and its template, as
    /// the create flow makes them: a library picture's bundled mosaic where it stands for the
    /// recipe (`MosaicMaker.bundled`), else the engine's. Polls task cancellation.
    @concurrent
    static func made(
        from photo: CGImage, recipe: MosaicEngine.Recipe, sampleName: String?, progress: (@Sendable (Double) -> Void)?
    ) async throws -> MosaicMaker.Made {
        let mosaic: Mosaic
        if let bundled = MosaicMaker.bundled(sampleName, recipe: recipe) {
            mosaic = bundled
        } else {
            let framed = MosaicMaker.framed(photo, panel: recipe.panel, centre: recipe.centre)
            let analysis = try await MosaicMaker.analyze(framed)
            mosaic = try MosaicMaker.make(framed, analysis: analysis, recipe: recipe, side: recipe.longSide,
                                          progress: { progress?($0) })
        }
        try Task.checkCancellation()
        return MosaicMaker.Made(mosaic: mosaic, template: try MosaicMaker.template(of: mosaic))
    }

    /// What an artwork's mosaic is made again from: the photo the create flow kept, the stored
    /// `source.jpg` (already cut to its panel, so laid whole, and never as a bundled mosaic of the
    /// whole picture), else the library picture it came from while the library still offers it
    /// (`Sample.named`), with the artwork's recipe; and the library picture whose bundled mosaic
    /// may stand for it.
    static func source(of artwork: Artwork, in store: ArtworkStore) throws
        -> (photo: CGImage, recipe: MosaicEngine.Recipe, sampleName: String?) {
        var recipe = artwork.recipe ?? MosaicEngine.Recipe()
        if store.hasSource(artwork.id) {
            let photo = try PhotoLoader.load(url: store.url(.source, of: artwork.id), maxPixelSize: ArtworkStore.sourceMaxPixelSize)
            guard let image = PhotoLoader.cgImage(from: photo) else { throw FactoryError.sourceUnavailable }
            guard recipe.panel != .whole else { return (image, recipe, artwork.sampleName) }
            recipe.panel = .whole
            recipe.centre = SIMD2(0.5, 0.5)
            return (image, recipe, nil)
        }
        guard let url = sampleURL(of: artwork) else { throw FactoryError.sourceUnavailable }
        let photo = try PhotoLoader.load(url: url, maxPixelSize: ArtworkStore.sourceMaxPixelSize)
        guard let image = PhotoLoader.cgImage(from: photo) else { throw FactoryError.sourceUnavailable }
        return (image, recipe, artwork.sampleName)
    }

    /// Whether `source(of:in:)` has a photo to regenerate the artwork from.
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
