import CoreGraphics
import Foundation
import PaintCore
import SwiftUI

/// A template's lines as the create flow's Line Art preview draws them (`CompareView`, Settings ›
/// Preview): a coloring book's drawing (its drawn edges and strokes, the lines
/// `TemplateRasterizer` draws for it), or a classic template's every edge between regions, in
/// canvas units. They are drawn as vectors at the zoom shown, so they stay crisp, and as heavy as
/// the canvas draws them (`ColoringBookLook`, `ClassicLook`). Over the finished painting, writing
/// over a paint too dark for the ink is drawn in the paper's tone (`paths(within:overPaint:)`).
nonisolated struct LineArtDrawing: Sendable, Identifiable {
    /// A polyline and its bounds, padded by a unit so straight lines get a box with area.
    nonisolated struct Line: Sendable {
        let points: [CGPoint]
        let bounds: CGRect
        /// Writing over a paint too dark for the ink (`DrawableLineArt.lightWriting`).
        let onDarkPaint: Bool

        init?(_ points: ArraySlice<SIMD2<Float>>, onDarkPaint: Bool = false) {
            guard points.count >= 2, let first = points.first else { return nil }
            var low = first, high = first
            for p in points {
                low = pointwiseMin(low, p)
                high = pointwiseMax(high, p)
            }
            self.points = points.map { CGPoint($0) }
            bounds = CGRect(
                x: CGFloat(low.x) - 1, y: CGFloat(low.y) - 1, width: CGFloat(high.x - low.x) + 2,
                height: CGFloat(high.y - low.y) + 2)
            self.onDarkPaint = onDarkPaint
        }
    }

    let id = UUID()
    /// The canvas, in canvas units.
    let size: CGSize
    /// Drawn as a coloring book (full ink, the book's weight), else as classic lines.
    let isColoringBook: Bool
    let lines: [Line]
    /// Every line in one path, for a frame showing most of the canvas, and over the painting the
    /// lines apart from the writing over dark paint, and that writing. Immutable once built.
    private let whole: UncheckedSendable<CGPath>
    private let wholeInk: UncheckedSendable<CGPath>
    private let wholeLight: UncheckedSendable<CGPath>
    /// Whether any line is writing over a paint too dark for the ink.
    let hasLightWriting: Bool

    init(_ t: Template) {
        size = CGSize(width: t.width, height: t.height)
        let drawable = DrawableLineArt(t)
        isColoringBook = drawable != nil
        var lines: [Line] = []
        for (e, edge) in t.edges.enumerated() where edge.right != BoundaryEdge.outside {
            if let drawable, !DrawableLineArt.isDrawn(drawable.edgeLayers[e]) { continue }
            if let line = Line(t.points(of: edge)) { lines.append(line) }
        }
        if let drawable {
            for (k, stroke) in drawable.strokes.enumerated() where DrawableLineArt.isDrawn(stroke.layer) {
                if let line = Line(drawable.points(of: stroke), onDarkPaint: drawable.lightWriting[k]) { lines.append(line) }
            }
        }
        self.lines = lines
        let path = CGMutablePath(), ink = CGMutablePath(), light = CGMutablePath()
        for line in lines {
            path.addLines(between: line.points)
            (line.onDarkPaint ? light : ink).addLines(between: line.points)
        }
        whole = UncheckedSendable(path.copy() ?? path)
        wholeInk = UncheckedSendable(ink.copy() ?? ink)
        wholeLight = UncheckedSendable(light.copy() ?? light)
        hasLightWriting = lines.contains(where: \.onDarkPaint)
    }

    /// The lines that pass through `rect` (canvas units): zoomed in, a frame strokes only what
    /// it shows. All of them while it shows half the canvas or more, where sorting them out
    /// would cost more than it saves.
    func path(within rect: CGRect) -> Path {
        if rect.width * rect.height >= 0.5 * size.width * size.height { return Path(whole.value) }
        var path = Path()
        for line in lines where line.bounds.intersects(rect) { path.addLines(line.points) }
        return path
    }

    /// `path(within:)` over the finished painting, where writing over a paint too dark for the ink
    /// is drawn in the paper's tone: the lines apart from that writing, and that writing. Without
    /// `overPaint` (on paper or a photo), all of them in the first.
    func paths(within rect: CGRect, overPaint: Bool) -> (ink: Path, light: Path) {
        guard overPaint, hasLightWriting else { return (path(within: rect), Path()) }
        if rect.width * rect.height >= 0.5 * size.width * size.height {
            return (Path(wholeInk.value), Path(wholeLight.value))
        }
        var ink = Path(), light = Path()
        for line in lines where line.bounds.intersects(rect) {
            if line.onDarkPaint { light.addLines(line.points) } else { ink.addLines(line.points) }
        }
        return (ink, light)
    }

    /// The lines' width on screen (points) for a picture `scale` times the size the painting's
    /// canvas fits it to: from that size up, the canvas's own width at that zoom; smaller, its
    /// fitted width scaled down with the picture, a miniature of the canvas, but never fainter
    /// than `minimumWidth`.
    func lineWidth(scale: CGFloat, weight: LineWeight) -> CGFloat {
        let depth = Float(log2(max(scale, 1)))
        let canvas = isColoringBook
            ? ColoringBookLook.widthPoints(depth: depth, weight: weight.factor) : ClassicLook.widthPoints(depth: depth)
        return max(CGFloat(canvas) * min(scale, 1), Self.minimumWidth)
    }

    /// The ink's opacity at that size: a book's drawing is in full ink, classic lines are as
    /// light as the canvas's on light paper.
    func inkOpacity(scale: CGFloat) -> Double {
        guard !isColoringBook else { return 1 }
        let depth = Float(log2(max(scale, 1)))
        return Double(CanvasPalette.light.outlineOpacity * ClassicLook.strength(depth: depth))
    }

    /// Half a point: a hairline at the screen's scale that still reads on paper.
    static let minimumWidth: CGFloat = 0.5

    /// The canvas sheet's paper and ink (`CanvasPalette.sheetPaperSRGB`, `sheetInkSRGB`).
    static let paper = Color(
        .sRGB, red: Double(CanvasPalette.sheetPaperSRGB.x), green: Double(CanvasPalette.sheetPaperSRGB.y),
        blue: Double(CanvasPalette.sheetPaperSRGB.z))
    static let ink = Color(
        .sRGB, red: Double(CanvasPalette.sheetInkSRGB.x), green: Double(CanvasPalette.sheetInkSRGB.y),
        blue: Double(CanvasPalette.sheetInkSRGB.z))
}
