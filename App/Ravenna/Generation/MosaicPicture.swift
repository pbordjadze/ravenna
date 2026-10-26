import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit

/// A mosaic drawn in its finish with Core Graphics, as v0 drew its walls (`App/v0/TileArt.swift`):
/// what drawing it needs, worked out once per finish, and the drawing of one tile. The create
/// flow's preview draws every tile set (`MosaicPicture.image`); the making-of bakes them in as they
/// settle and draws those still in flight. Canvas units, y down. Plain Core Graphics, drawn off the
/// main actor.
nonisolated struct MosaicDrawing: @unchecked Sendable {
    let finish: Finish
    var paths: [CGPath] = []
    var corners: [[SIMD2<Float>]] = []
    var centres: [CGPoint] = []
    var boxes: [CGRect] = []
    /// A tile's size: the side of a square of its bounds' area.
    var sizes: [CGFloat] = []
    var body: [SIMD3<Float>] = []
    var clockwise: [Bool] = []
    var stone: [Bool] = []
    var gold: [Bool] = []

    init(_ m: Mosaic, finish: Finish) {
        self.finish = finish
        let golds = m.palette.map(TileColor.isGold)
        for (i, t) in m.tiles.enumerated() {
            let p = CGMutablePath()
            p.addLines(between: t.corners.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            p.closeSubpath()
            paths.append(p)
            corners.append(t.corners)
            let b = p.boundingBox
            boxes.append(b)
            sizes.append((b.width * b.height).squareRoot())
            centres.append(CGPoint(x: CGFloat(t.centre.x), y: CGFloat(t.centre.y)))
            body.append(TileColor.body(m.palette[t.paint], tile: i, finish: finish))
            clockwise.append(Light.clockwise(t.corners))
            stone.append(t.stone)
            gold.append(golds[t.paint])
        }
    }

    /// Draws a set tile in its finish.
    func draw(_ i: Int, in cg: CGContext) {
        let path = paths[i], c = body[i]
        cg.saveGState()
        defer { cg.restoreGState() }
        switch finish {
        case .flat:
            cg.addPath(path); cg.setFillColor(color(c)); cg.fillPath()
            cg.addPath(path); cg.setStrokeColor(CGColor(srgbRed: 0.2, green: 0.18, blue: 0.17, alpha: 1))
            cg.setLineWidth(0.5); cg.strokePath()
        case .bed:
            cg.addPath(path); cg.setFillColor(color(c)); cg.fillPath()
        case .material:
            cg.addPath(path); cg.clip()
            cg.setFillColor(color(c)); cg.fill(boxes[i])
            // A lit upper-left edge and a shaded lower-right one: glass sharper than stone.
            let pts = corners[i], k: Float = stone[i] ? 0.16 : 0.34
            cg.setLineWidth(sizes[i] * (stone[i] ? 0.2 : 0.28))
            for j in pts.indices {
                let a = pts[j], b = pts[(j + 1) % pts.count]
                let l = Light.edge(a, b, clockwise: clockwise[i])
                cg.setStrokeColor(color(c * (1 + k * l) + (l > 0 ? 0.03 * l : 0)))
                cg.move(to: point(a)); cg.addLine(to: point(b)); cg.strokePath()
            }
            if !stone[i] {
                // Glass glints toward the corner the light reaches first.
                let p = point(pts[Light.litCorner(pts)])
                cg.drawRadialGradient(Self.glow, startCenter: p, startRadius: 0, endCenter: p,
                                      endRadius: sizes[i] * 0.55, options: [])
            }
        }
    }

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated(unsafe) static let glow = CGGradient(
        colorsSpace: space,
        colors: [CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0.16), CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0)] as CFArray,
        locations: [0, 1])!

    func color(_ v: SIMD3<Float>, _ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(min(max(v.x, 0), 1)), green: CGFloat(min(max(v.y, 0), 1)), blue: CGFloat(min(max(v.z, 0), 1)),
                alpha: alpha)
    }

    private func point(_ v: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)) }
}

/// The ground a mosaic is set on, and the whole of it drawn finished.
nonisolated enum MosaicPicture {
    /// The painted bed under the tiles (`MosaicEngine.bed`) at `width` × `height` px, with a
    /// red-brown bole under a gold ground's tiles (`Mosaic.goldGround`), so their joints are warm
    /// rather than the old background's colour.
    static func bed(of m: Mosaic, width: Int, height: Int) -> CGImage? {
        let rgb = MosaicEngine.bed(of: m, width: width, height: height)
        guard let flat = image(rgb, width, height) else { return nil }
        let gold = m.palette.indices.filter { m.palette[$0] == Mosaic.groundGold }
        guard let paint = gold.last, m.width > 0,
              let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: MosaicDrawing.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return flat }
        cg.draw(flat, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Canvas units, y down.
        let k = CGFloat(width) / CGFloat(m.width)
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: k, y: -k)
        cg.setFillColor(CGColor(srgbRed: 0.6, green: 0.33, blue: 0.2, alpha: 1))
        for t in m.tiles where t.paint == paint {
            // A little wider than the tile, to fill the joints round it.
            let c = t.centre, grown = t.corners.map { c + ($0 - c) * 1.35 }
            guard let first = grown.first else { continue }
            cg.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
            for p in grown.dropFirst() { cg.addLine(to: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))) }
            cg.closePath()
            cg.fillPath()
        }
        return cg.makeImage() ?? flat
    }

    /// The mosaic finished, every tile set in `finish`, at most `longest` px on its long side: on
    /// the painted bed, or on light grout for the flat finish. `drawing` saves working it out again.
    static func image(_ m: Mosaic, finish: Finish, longest: CGFloat, drawing: MosaicDrawing? = nil) -> CGImage? {
        guard m.width > 0, m.height > 0 else { return nil }
        let scale = longest / CGFloat(max(m.width, m.height))
        let w = max(Int((CGFloat(m.width) * scale).rounded()), 1), h = max(Int((CGFloat(m.height) * scale).rounded()), 1)
        guard let cg = canvas(for: m, width: w, height: h) else { return nil }
        ground(m, finish: finish, in: cg, width: w, height: h)
        let drawing = drawing ?? MosaicDrawing(m, finish: finish)
        for i in drawing.paths.indices { drawing.draw(i, in: cg) }
        return cg.makeImage()
    }

    /// A context `width` × `height` px drawing in the mosaic's canvas units, y down.
    static func canvas(for m: Mosaic, width: Int, height: Int) -> CGContext? {
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: MosaicDrawing.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: CGFloat(width) / CGFloat(m.width), y: -CGFloat(height) / CGFloat(m.height))
        cg.interpolationQuality = .high
        return cg
    }

    /// The bed (or the light grout, for the flat finish) over the whole of a context from `canvas`.
    static func ground(_ m: Mosaic, finish: Finish, in cg: CGContext, width: Int, height: Int, bed: CGImage? = nil) {
        let wall = CGRect(x: 0, y: 0, width: CGFloat(m.width), height: CGFloat(m.height))
        if finish.paintedBed, let bed = bed ?? Self.bed(of: m, width: width, height: height) {
            cg.saveGState()
            cg.translateBy(x: 0, y: CGFloat(m.height))
            cg.scaleBy(x: 1, y: -1)
            cg.draw(bed, in: wall)
            cg.restoreGState()
        } else {
            cg.setFillColor(CGColor(srgbRed: CGFloat(m.grout.x), green: CGFloat(m.grout.y), blue: CGFloat(m.grout.z), alpha: 1))
            cg.fill(wall)
        }
    }

    static func image(_ rgb: [SIMD3<Float>], _ w: Int, _ h: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<min(rgb.count, w * h) {
            let c = rgb[i]
            bytes[i * 4] = UInt8(min(max(c.x, 0), 1) * 255)
            bytes[i * 4 + 1] = UInt8(min(max(c.y, 0), 1) * 255)
            bytes[i * 4 + 2] = UInt8(min(max(c.z, 0), 1) * 255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: MosaicDrawing.space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
