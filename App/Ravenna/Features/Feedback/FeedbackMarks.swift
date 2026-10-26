import CoreGraphics
import Foundation
import PaintCore
import simd

/// One stroke of feedback ink in canvas units: the visible part of a PencilKit stroke as a
/// polyline (a stroke the pixel eraser cut through is several).
nonisolated struct FeedbackStroke: Sendable, Equatable {
    /// On-curve points a couple of canvas units apart.
    var points: [SIMD2<Float>]
    /// Ink width in canvas units.
    var width: Float
    /// The kind of ink ("pen", "marker", …) and its sRGB color as `#RRGGBB`.
    var ink: String
    var color: String
    /// Points on screen per canvas unit while it was drawn: how large the painter saw it.
    var zoom: Float
    /// When it was drawn.
    var date: Date

    /// Highlighter ink marks areas; the other inks also write.
    var isHighlight: Bool { ink == "marker" }

    /// The points' bounds grown by half the ink's width.
    var bounds: CGRect {
        guard let first = points.first else { return .null }
        var low = first, high = first
        for p in points.dropFirst() {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        let half = CGFloat(width) / 2
        return CGRect(x: CGFloat(low.x), y: CGFloat(low.y), width: CGFloat(high.x - low.x), height: CGFloat(high.y - low.y))
            .insetBy(dx: -half, dy: -half)
    }

    /// Whether it closes on itself, like a circle drawn round something: long enough, its ends
    /// close together for its size.
    var isLoop: Bool {
        guard points.count >= 8, let first = points.first, let last = points.last else { return false }
        let box = bounds
        let extent = Float(max(box.width, box.height))
        return extent >= 6 * width && simd_distance(first, last) <= max(0.3 * extent, 2 * width)
    }
}

/// Strokes drawn close together, which feedback treats as one remark: a circle and the words
/// beside it, an arrow and what it points at.
nonisolated struct FeedbackMark: Sendable, Equatable, Identifiable {
    /// The time its first stroke was drawn: it stays while that stroke does, so a comment keeps
    /// to its mark as other strokes come and go.
    var id: Date
    /// Its strokes (indices into the strokes it was grouped from), in drawing order.
    var strokes: [Int]
    /// Canvas units, ink included.
    var bounds: CGRect
}

/// A region a mark touches: how many of its pixels (canvas units) lie under the ink, and how
/// many inside a loop the mark closes (a circle drawn round an area means the area).
nonisolated struct FeedbackRegionHit: Sendable, Equatable, Codable {
    var region: Int
    /// Palette index (the painting numbers it `color + 1`).
    var color: Int
    var inked: Int
    var enclosed: Int
}

nonisolated enum FeedbackMarks {
    /// Strokes whose ink came within this many points on screen of each other, at the zoom
    /// they were drawn at, belong to one mark.
    static let reach: Float = 36

    /// The marks `strokes` make, in the order they were begun.
    static func group(_ strokes: [FeedbackStroke]) -> [FeedbackMark] {
        let grown = strokes.map { stroke -> CGRect in
            let margin = CGFloat(reach / max(stroke.zoom, 0.01)) / 2
            return stroke.bounds.insetBy(dx: -margin, dy: -margin)
        }
        var parent = Array(strokes.indices)
        func root(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            var c = i
            while parent[c] != r {
                let next = parent[c]
                parent[c] = r
                c = next
            }
            return r
        }
        for i in strokes.indices where !grown[i].isNull {
            for j in strokes.indices where j > i && !grown[j].isNull && grown[i].intersects(grown[j]) {
                let (a, b) = (root(i), root(j))
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var members: [Int: [Int]] = [:]
        for i in strokes.indices where !grown[i].isNull { members[root(i), default: []].append(i) }
        return members.values
            .map { group -> FeedbackMark in
                let ordered = group.sorted { (strokes[$0].date, $0) < (strokes[$1].date, $1) }
                let bounds = ordered.reduce(CGRect.null) { $0.union(strokes[$1].bounds) }
                return FeedbackMark(id: strokes[ordered[0]].date, strokes: ordered, bounds: bounds)
            }
            .sorted { ($0.id, $0.strokes[0]) < ($1.id, $1.strokes[0]) }
    }

    /// The regions under `mark`'s ink or inside its loops, most covered first, at most `limit`:
    /// the ink is drawn into a mask at one pixel per canvas unit and read against the region map.
    static func regions(of mark: FeedbackMark, strokes: [FeedbackStroke], in template: Template, limit: Int = 40) -> [FeedbackRegionHit] {
        let map = template.regionMap
        let box = mark.bounds.intersection(CGRect(x: 0, y: 0, width: map.width, height: map.height)).integral
        guard !box.isNull, box.width >= 1, box.height >= 1 else { return [] }
        let ink = mask(box) { ctx in
            for i in mark.strokes { Self.stroke(strokes[i], in: ctx) }
        }
        let loops = mask(box) { ctx in
            for i in mark.strokes where strokes[i].isLoop {
                ctx.addLines(between: strokes[i].points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                ctx.closePath()
                ctx.fillPath()
            }
        }
        let x0 = Int(box.minX), y0 = Int(box.minY), w = Int(box.width), h = Int(box.height)
        var inked: [Int: Int] = [:], enclosed: [Int: Int] = [:]
        for row in 0..<h {
            for column in 0..<w {
                let region = Int(map[x0 + column, y0 + row])
                guard region < template.regions.count else { continue }
                if ink[row * w + column] >= 128 {
                    inked[region, default: 0] += 1
                } else if loops[row * w + column] >= 128 {
                    enclosed[region, default: 0] += 1
                }
            }
        }
        let hits = Set(inked.keys).union(enclosed.keys).map { region in
            FeedbackRegionHit(
                region: region, color: Int(template.regions[region].colorIndex),
                inked: inked[region] ?? 0, enclosed: enclosed[region] ?? 0)
        }
        return Array(hits.sorted { ($1.inked + $1.enclosed, $0.region) < ($0.inked + $0.enclosed, $1.region) }.prefix(limit))
    }

    /// Draws `stroke` as a round-capped line of its width (a dot when it has no length).
    private static func stroke(_ stroke: FeedbackStroke, in ctx: CGContext) {
        let width = max(CGFloat(stroke.width), 1)
        let points = stroke.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        guard let first = points.first else { return }
        if points.count < 2 {
            ctx.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
            return
        }
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addLines(between: points)
        ctx.strokePath()
    }

    /// A white-on-black 8-bit mask of `box` (canvas units, one pixel each), drawn in canvas
    /// coordinates (y down); row 0 is the box's top.
    private static func mask(_ box: CGRect, draw: (CGContext) -> Void) -> [UInt8] {
        let w = Int(box.width), h = Int(box.height)
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.setStrokeColor(gray: 1, alpha: 1)
            draw(ctx)
        }
        return pixels
    }
}
