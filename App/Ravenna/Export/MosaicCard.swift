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
///   .paintingPNG`, `CompletionShare`): `keepsake`, about 3,000 px, with the border Settings
///   chooses (`Border`, v0's `Keepsake`).
nonisolated enum MosaicCard {
    /// The card as PNG, at most `maxPixelSize` px on its long side; nil when `painted` (one flag per
    /// template region: tile i, then the grout) doesn't fit the mosaic.
    static func pngData(_ m: Mosaic, painted: [Bool], maxPixelSize: Int) -> Data? {
        image(m, painted: painted, maxPixelSize: maxPixelSize).flatMap(ImageCodec.pngData)
    }

    /// The picture to share: a finished wall has no outlines left, one begun shows where its tiles
    /// still go; with the border round it.
    static func keepsake(_ m: Mosaic, painted: [Bool], border: Border = TileOptions.border(), maxPixelSize: Int = 3000) -> CGImage? {
        guard let wall = image(m, painted: painted, maxPixelSize: maxPixelSize) else { return nil }
        // Every tile set (the grout, the last region, set or not).
        let finished = !painted.dropLast().contains(false)
        return border.around(wall, m, finished: finished) ?? wall
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

/// What goes round a shared mosaic (v0's option, its key `border`): nothing, a margin of lime
/// plaster, or a band of square tesserae in the plaster, as a panel's border is laid.
nonisolated enum Border: String, CaseIterable, Sendable {
    case none, plaster, band

    /// `wall` with the border round it, or nil for none. The band alternates the mosaic's darkest
    /// paint with gold on a finished wall, or with its lightest paint on one in progress.
    func around(_ wall: CGImage, _ m: Mosaic, finished: Bool) -> CGImage? {
        guard self != .none, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = CGFloat(wall.width), h = CGFloat(wall.height)
        let tile = max(w, h) / 90, gap = tile * 0.16
        let margin = self == .band ? tile * 3.2 : tile * 1.6
        let size = CGSize(width: w + 2 * margin, height: h + 2 * margin)
        guard let cg = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(red: 0.914, green: 0.886, blue: 0.827, alpha: 1)  // Theme's lime plaster
        cg.fill(CGRect(origin: .zero, size: size))
        cg.draw(wall, in: CGRect(x: margin, y: margin, width: w, height: h))
        guard self == .band else { return cg.makeImage() }
        let luma = { (c: SIMD3<Float>) in 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
        let dark = m.palette.min { luma($0) < luma($1) } ?? SIMD3(0.1, 0.1, 0.1)
        let light = finished ? Mosaic.groundGold : (m.palette.max { luma($0) < luma($1) } ?? SIMD3(0.9, 0.9, 0.9))
        // The band's centre line, a tile and a bit in from the edge; tiles fitted evenly along each side.
        let inset = tile * 0.9 + tile / 2
        let ring = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        var k = 0
        for (a, b) in [(CGPoint(x: ring.minX, y: ring.minY), CGPoint(x: ring.maxX, y: ring.minY)),
                       (CGPoint(x: ring.maxX, y: ring.minY), CGPoint(x: ring.maxX, y: ring.maxY)),
                       (CGPoint(x: ring.maxX, y: ring.maxY), CGPoint(x: ring.minX, y: ring.maxY)),
                       (CGPoint(x: ring.minX, y: ring.maxY), CGPoint(x: ring.minX, y: ring.minY))] {
            let length = hypot(b.x - a.x, b.y - a.y), n = max(1, Int((length / (tile + gap)).rounded()))
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n)
                let c = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let j = { (salt: UInt64) in CGFloat(TileColor.wobble(k, salt: salt)) * tile * 0.05 }
                let body = k.isMultiple(of: 2) ? dark : light
                cg.setFillColor(red: CGFloat(body.x), green: CGFloat(body.y), blue: CGFloat(body.z), alpha: 1)
                let half = (tile - gap) / 2
                cg.beginPath()
                cg.move(to: CGPoint(x: c.x - half + j(1), y: c.y - half + j(2)))
                cg.addLine(to: CGPoint(x: c.x + half + j(3), y: c.y - half + j(4)))
                cg.addLine(to: CGPoint(x: c.x + half + j(5), y: c.y + half + j(6)))
                cg.addLine(to: CGPoint(x: c.x - half + j(7), y: c.y + half + j(8)))
                cg.closePath()
                cg.fillPath()
                k += 1
            }
        }
        return cg.makeImage()
    }
}
