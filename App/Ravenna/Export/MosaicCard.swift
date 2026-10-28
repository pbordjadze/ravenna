import CoreGraphics
import Foundation
import MosaicKit

/// A mosaic as a picture, drawn with the engine's CPU drawing (`MosaicPicture`, `MosaicDrawing`) in
/// the app's finish (`MosaicLook`), as v0's covers and keepsakes were: its ground (the painted bed,
/// or light grout for the flat finish), the places of tiles still to set faint on it, and every tile
/// set so far. Ravenna's seam: Paint by Moonlight draws these as paint on its light paper
/// (`TemplateRasterizer`, `CanvasSnapshot`), which glared on Ravenna's dark gallery and lost the
/// tiles from a shared wall.
///
/// - The gallery's card (`Library.thumbnailPNG`): `pngData`.
/// - The picture shared, saved or printed from a finished or begun mosaic (`ArtworkExporter
///   .paintingPNG`, `CompletionShare`): `keepsake`, about 3,000 px, with nothing round it (v0's
///   `Keepsake` offered a border; Paul kept none, October 28).
nonisolated enum MosaicCard {
    /// The card as PNG, at most `maxPixelSize` px on its long side; nil when `painted` (one flag per
    /// template region: tile i, then the grout) doesn't fit the mosaic.
    static func pngData(_ m: Mosaic, painted: [Bool], maxPixelSize: Int) -> Data? {
        image(m, painted: painted, maxPixelSize: maxPixelSize).flatMap(ImageCodec.pngData)
    }

    /// The picture to share: a finished wall has no outlines left, one begun shows where its tiles
    /// still go.
    static func keepsake(_ m: Mosaic, painted: [Bool], maxPixelSize: Int = 3000) -> CGImage? {
        image(m, painted: painted, maxPixelSize: maxPixelSize)
    }

    /// The painted bed's long side at most, as the canvas's (`TileScene.bed`).
    static let bedLongSide = 1024

    static func image(_ m: Mosaic, painted: [Bool], maxPixelSize: Int) -> CGImage? {
        guard m.width > 0, m.height > 0, !m.tiles.isEmpty, painted.count == m.tiles.count + 1 else { return nil }
        let finish = MosaicLook.current.finish
        let scale = CGFloat(maxPixelSize) / CGFloat(max(m.width, m.height))
        let w = max(Int((CGFloat(m.width) * scale).rounded()), 1), h = max(Int((CGFloat(m.height) * scale).rounded()), 1)
        guard let cg = MosaicPicture.canvas(for: m, width: w, height: h) else { return nil }
        // The bed is a blur: made at no more than `bedLongSide` and scaled up, a keepsake's costs
        // what the canvas's does rather than hundreds of megabytes.
        let k = min(1, CGFloat(Self.bedLongSide) / CGFloat(max(w, h)))
        let bed = finish.paintedBed
            ? MosaicPicture.bed(of: m, width: max(Int((CGFloat(w) * k).rounded()), 1), height: max(Int((CGFloat(h) * k).rounded()), 1))
            : nil
        MosaicPicture.ground(m, finish: finish, in: cg, width: w, height: h, bed: bed)
        let drawing = MosaicDrawing(m, finish: finish)
        // The places still to set, as v0's covers drew them: faint on the bed, grey on light grout.
        let unset = drawing.paths.indices.filter { !painted[$0] }
        if !unset.isEmpty {
            for i in unset { cg.addPath(drawing.paths[i]) }
            cg.setStrokeColor(finish.paintedBed
                ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35) : CGColor(srgbRed: 0.55, green: 0.52, blue: 0.48, alpha: 1))
            cg.setLineWidth(1.2 / scale)
            cg.strokePath()
        }
        for i in drawing.paths.indices where painted[i] { drawing.draw(i, in: cg) }
        return cg.makeImage()
    }
}
