import CoreGraphics
import UIKit

/// What drawing a mosaic needs, worked out once per finish, and the drawing of one tile in it with
/// Core Graphics: the same code bakes set tiles into the wall's image and draws tiles still settling.
/// Canvas units, y down. Plain Core Graphics, so walls and covers are drawn off the main thread.
nonisolated struct Drawing: @unchecked Sendable {
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

    /// The outline of a tile not yet set.
    var outline: CGColor {
        finish.paintedBed ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35) : CGColor(srgbRed: 0.55, green: 0.52, blue: 0.48, alpha: 1)
    }

    /// Draws a set tile in its finish; `glint` (0...1) is the light crossing it as it settles.
    func draw(_ i: Int, in cg: CGContext, glint: Double? = nil) {
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
        if let g = glint { catchLight(i, g, in: cg) }
    }

    /// A band of warm light crossing the tile from its lit corner, once: gold catching the light
    /// where a tile is being set, and only there.
    private func catchLight(_ i: Int, _ g: Double, in cg: CGContext) {
        cg.addPath(paths[i]); cg.clip()
        let b = boxes[i], pad = max(b.width, b.height) * 0.4
        let peak = (gold[i] ? 0.75 : stone[i] ? 0.2 : 0.45) * sin(.pi * g)
        let at = CGFloat(0.12 + 0.76 * g)
        let warm = gold[i] ? SIMD3<Float>(1, 0.89, 0.59) : SIMD3<Float>(1, 0.95, 0.84)
        let band = CGGradient(colorsSpace: Self.space, colors: [color(warm, 0), color(warm, peak), color(warm, 0)] as CFArray,
                              locations: [at - 0.12, at, at + 0.12])!
        cg.drawLinearGradient(band, start: CGPoint(x: b.minX - pad, y: b.minY - pad), end: CGPoint(x: b.maxX + pad, y: b.maxY + pad), options: [])
        if gold[i] {
            cg.setFillColor(CGColor(srgbRed: 0.79, green: 0.64, blue: 0.29, alpha: 0.35 * (1 - g)))
            cg.fill(b)
        }
    }

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    nonisolated(unsafe) static let glow = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0.16),
                                                              CGColor(srgbRed: 1, green: 0.98, blue: 0.92, alpha: 0)] as CFArray,
                                 locations: [0, 1])!

    private func color(_ v: SIMD3<Float>, _ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(min(max(v.x, 0), 1)), green: CGFloat(min(max(v.y, 0), 1)), blue: CGFloat(min(max(v.z, 0), 1)), alpha: alpha)
    }

    private func point(_ v: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)) }
}

/// The wall as an image: its ground, the outlines of tiles to set, and every set tile, baked as it
/// goes in, so a wall of thousands moves as lightly as one of a few hundred. Made off the main thread
/// and then used only on it.
nonisolated final class WallImage: @unchecked Sendable {
    let drawing: Drawing
    /// Image pixels per canvas unit.
    let scale: CGFloat
    private let context: CGContext
    private let bed: CGImage?
    private let grout: CGColor
    private let size: CGSize
    private(set) var baked = Set<Int>()
    private var image: CGImage?

    /// `longest`: the image's longest side in pixels; `outlines`: draw the places of tiles to set.
    init?(_ m: Mosaic, drawing: Drawing, bed: CGImage?, longest: CGFloat = 3200, outlines: Bool = true) {
        size = CGSize(width: CGFloat(m.width), height: CGFloat(m.height))
        scale = min(3, longest / max(size.width, size.height))
        guard let cg = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                 bytesPerRow: 0, space: Drawing.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Canvas units, y down.
        cg.translateBy(x: 0, y: size.height * scale)
        cg.scaleBy(x: scale, y: -scale)
        cg.interpolationQuality = .high
        context = cg
        self.drawing = drawing
        self.bed = drawing.finish.paintedBed ? bed.map { Self.bole(under: $0, m) ?? $0 } : nil
        grout = CGColor(srgbRed: CGFloat(m.grout.x), green: CGFloat(m.grout.y), blue: CGFloat(m.grout.z), alpha: 1)
        ground()
        guard outlines else { return }
        cg.setStrokeColor(drawing.outline)
        cg.setLineWidth(1.2 / scale)
        for p in drawing.paths { cg.addPath(p) }
        cg.strokePath()
    }

    /// A wall with the painter's tiles set, made in one go: for the bench, a cover, or sharing.
    static func make(_ m: Mosaic, _ finish: Finish, bed: CGImage?, set: Set<Int>, drawing: Drawing? = nil,
                     longest: CGFloat = 3200, outlines: Bool = true) -> WallImage? {
        let image = WallImage(m, drawing: drawing ?? Drawing(m, finish: finish), bed: bed, longest: longest, outlines: outlines)
        image?.bake(set.sorted())
        return image
    }

    /// Bakes set tiles in; answers whether any were new.
    @discardableResult
    func bake(_ tiles: some Sequence<Int>) -> Bool {
        var any = false
        for i in tiles where drawing.paths.indices.contains(i) && baked.insert(i).inserted {
            // Lift its outline off the ground first, then set it.
            context.saveGState()
            context.addPath(drawing.paths[i])
            context.setLineWidth(3 / scale)
            context.replacePathWithStrokedPath()
            context.addPath(drawing.paths[i])
            context.clip()
            ground()
            context.restoreGState()
            drawing.draw(i, in: context)
            any = true
        }
        if any { image = nil }
        return any
    }

    /// The wall as it stands.
    var current: CGImage? {
        if image == nil { image = context.makeImage() }
        return image
    }

    /// The painted bed with a red-brown bole under the gold ground's tiles (`Mosaic.goldGround`),
    /// so their joints are warm rather than the old background's colour; nil when there's no gold
    /// ground.
    private static func bole(under bed: CGImage, _ m: Mosaic) -> CGImage? {
        let gold = m.palette.indices.filter { m.palette[$0] == Mosaic.groundGold }
        guard let paint = gold.last, m.width > 0,
              let cg = CGContext(data: nil, width: bed.width, height: bed.height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: Drawing.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.draw(bed, in: CGRect(x: 0, y: 0, width: bed.width, height: bed.height))
        // Canvas units, y down.
        let k = CGFloat(bed.width) / CGFloat(m.width)
        cg.translateBy(x: 0, y: CGFloat(bed.height))
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
        return cg.makeImage()
    }

    private func ground() {
        let wall = CGRect(origin: .zero, size: size)
        if let bed {
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(bed, in: wall)
            context.restoreGState()
        } else {
            context.setFillColor(grout)
            context.fill(wall)
        }
    }
}
