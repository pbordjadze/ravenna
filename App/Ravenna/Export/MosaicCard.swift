import CoreGraphics
import Foundation
import MosaicKit

/// A mosaic's gallery card (its thumbnail), as v0's covers were: the ground it is set on (the
/// painted bed, or light grout for the flat finish), the places of tiles still to set drawn faintly
/// on it, and every tile set so far in the app's finish (`MosaicLook`), with the engine's CPU drawing
/// (`MosaicPicture`, `MosaicDrawing`). Ravenna's seam: Paint by Moonlight's cards are its light
/// paper with the template's lines (`TemplateRasterizer`), which glared on Ravenna's dark gallery.
nonisolated enum MosaicCard {
    /// The card as PNG, at most `maxPixelSize` px on its long side; nil when `painted` (one flag per
    /// template region: tile i, then the grout) doesn't fit the mosaic.
    static func pngData(_ m: Mosaic, painted: [Bool], maxPixelSize: Int) -> Data? {
        image(m, painted: painted, maxPixelSize: maxPixelSize).flatMap(ImageCodec.pngData)
    }

    static func image(_ m: Mosaic, painted: [Bool], maxPixelSize: Int) -> CGImage? {
        guard m.width > 0, m.height > 0, !m.tiles.isEmpty, painted.count == m.tiles.count + 1 else { return nil }
        let finish = MosaicLook.current.finish
        let scale = CGFloat(maxPixelSize) / CGFloat(max(m.width, m.height))
        let w = max(Int((CGFloat(m.width) * scale).rounded()), 1), h = max(Int((CGFloat(m.height) * scale).rounded()), 1)
        guard let cg = MosaicPicture.canvas(for: m, width: w, height: h) else { return nil }
        MosaicPicture.ground(m, finish: finish, in: cg, width: w, height: h)
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
