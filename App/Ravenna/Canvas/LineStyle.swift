import Foundation
import PaintCore
import simd

/// How a classic template's lines draw on the canvas: every region boundary one even line,
/// lighter and finer zoomed out, where regions are small on screen. Pictures draw it at their
/// style's own width and color (`TemplateRasterizer.Style`).
nonisolated enum ClassicLook {
    /// The line's opacity as a fraction of the paper's full ink, `depth` zoom doublings in.
    static func strength(depth: Float) -> Float { min(1, 0.7 + 0.15 * depth) }

    /// The line's width on the canvas (points), `depth` zoom doublings in.
    static func widthPoints(depth: Float) -> Float { min(1.0, 0.5 + 0.22 * depth) }
}

/// How a template with line art draws, the same in every renderer: as a coloring book, which
/// every template the app makes is (a template of the retired layered style too): every drawn
/// layer alike, in the paper's full ink, heavy at every zoom, never dissolving under the paint;
/// color edges (the paints inside an outline) never drawn, and the selected color's cells never
/// outlined, since the fill's highlight shows them. Only the weight is the painter's
/// (`LineWeight`).
nonisolated enum ColoringBookLook {
    /// A book line in pictures (thumbnails, share images, print), as a factor on the picture's
    /// classic line: three times as heavy, the canvas's ratio with the painting fitted.
    static let widthFactor: Float = 3

    /// The canvas's book line (points), `depth` zoom doublings in: 1.5 pt fitted (three times
    /// the classic line there), growing with the zoom but far slower than the drawing, so zoomed
    /// in it reads as a pen line, not a band. Times `weight` (`LineWeight.factor`).
    static func widthPoints(depth: Float, weight: Float) -> Float { (1.5 + 0.7 * max(depth, 0)) * weight }

    /// The ink pictures draw the book with: the canvas sheet's ink, encoded sRGB.
    static let ink = SIMD4(CanvasPalette.sheetInkSRGB, 1)

    /// On paper there is no highlight to show a color's cells, so a printed book draws its color
    /// edges as dotted guides: this fraction of the printable style's outline opacity, dots this
    /// many line widths apart.
    static let printedGuideOpacity: Float = 0.7
    static let printedGuideSpacing: CGFloat = 2.5
}

/// A template's line art checked against the template, ready to draw: a layer per boundary
/// edge, and the interior strokes that fit. Renderers never index with unchecked line data
/// (PaintCore's decoder checks files too; this keeps a malformed template drawable as classic
/// instead of trapping).
nonisolated struct DrawableLineArt: Sendable {
    /// Layer (`LineLayer` raw value) per `Template.edges` entry.
    let edgeLayers: [UInt8]
    /// The template's strokes that are well formed, in their order.
    let strokes: [InteriorStroke]
    /// Per stroke of `strokes`: whether it is writing over a paint too dark for the sheet's ink
    /// (`Template.writesOnDarkPaint`), which draws in the paper's light tone once painted.
    let lightWriting: [Bool]
    let strokePoints: [SIMD2<Float>]

    /// nil for classic templates, and for line art that doesn't match the template's edges.
    init?(_ t: Template) {
        guard let art = t.lineArt, art.edgeLayers.count == t.edges.count, art.edgeWeights.count == t.edges.count else {
            return nil
        }
        let maxLayer = LineLayer.color.rawValue
        let points = art.strokePoints.count, regions = t.regions.count
        var strokes: [InteriorStroke] = [], lightWriting: [Bool] = []
        for (k, s) in art.strokes.enumerated()
        where s.pointCount >= 2 && Int(s.pointStart) + Int(s.pointCount) <= points && Int(s.region) < regions && s.layer <= maxLayer {
            strokes.append(s)
            lightWriting.append(t.writesOnDarkPaint(stroke: k))
        }
        edgeLayers = art.edgeLayers.map { min($0, maxLayer) }
        self.strokes = strokes
        self.lightWriting = lightWriting
        strokePoints = art.strokePoints
    }

    /// Whether a line of `layer` is part of the drawing (a coloring book draws these alike and
    /// nothing else): PaintCore's rule, which Refine's gestures read too.
    static func isDrawn(_ layer: UInt8) -> Bool { LineLayer.isDrawn(layer) }

    func points(of stroke: InteriorStroke) -> ArraySlice<SIMD2<Float>> {
        strokePoints[Int(stroke.pointStart)..<Int(stroke.pointStart + stroke.pointCount)]
    }
}

/// What the outline pass draws for a template: a "line" per boundary edge, then one per interior
/// stroke, each with its two regions and its layer, and a segment per step of every line's
/// polyline. A stroke has its region on both sides, which the shader reads as "inside a cell".
/// Classic templates get exactly the segments and regions they always had, every line in layer 0.
/// Writing over a paint too dark for the ink (`DrawableLineArt.lightWriting`) has
/// `lightWritingMark` added to its layer: the shader turns it to the light tone as its region is
/// painted.
nonisolated struct OutlineGeometry {
    /// Added to a stroke's layer when it is writing over a paint too dark for the ink; the
    /// shader's `kLightWriting` (Shaders.metal).
    static let lightWritingMark: Float = 4

    /// Boundary points, then stroke points.
    let points: [SIMD2<Float>]
    /// (first point, line) per segment.
    let segments: [SIMD2<UInt32>]
    /// (left, right) region per line; `BoundaryEdge.outside` on the right of a canvas border edge.
    let lineRegions: [SIMD2<UInt32>]
    /// `LineLayer` raw value per line, plus `lightWritingMark` for writing over a dark paint.
    let lineLayers: [Float]
    /// Whether the lines draw as a coloring book (`ColoringBookLook`): the template has line art.
    let isColoringBook: Bool

    init(_ t: Template) {
        let lines = DrawableLineArt(t)
        let strokes = lines?.strokes ?? []
        var segs: [SIMD2<UInt32>] = []
        segs.reserveCapacity(max(0, t.points.count - t.edges.count) + (lines?.strokePoints.count ?? 0))
        var regions: [SIMD2<UInt32>] = []
        regions.reserveCapacity(t.edges.count + strokes.count)
        var layers: [Float] = []
        layers.reserveCapacity(t.edges.count + strokes.count)
        for (e, edge) in t.edges.enumerated() {
            regions.append(SIMD2(edge.left, edge.right))
            layers.append(lines.map { Float($0.edgeLayers[e]) } ?? 0)
            guard edge.pointCount >= 2 else { continue }
            for k in 0..<(edge.pointCount - 1) { segs.append(SIMD2(edge.pointStart + k, UInt32(e))) }
        }
        var points = t.points
        if let lines {
            let base = UInt32(t.points.count)
            points.append(contentsOf: lines.strokePoints)
            for (s, stroke) in strokes.enumerated() {
                let line = UInt32(t.edges.count + s)
                regions.append(SIMD2(stroke.region, stroke.region))
                layers.append(Float(stroke.layer) + (lines.lightWriting[s] ? Self.lightWritingMark : 0))
                for k in 0..<(stroke.pointCount - 1) { segs.append(SIMD2(base + stroke.pointStart + k, line)) }
            }
        }
        self.points = points
        segments = segs
        lineRegions = regions
        lineLayers = layers
        isColoringBook = lines != nil
    }
}
