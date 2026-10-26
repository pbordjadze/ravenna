import CoreGraphics
import Foundation
import PencilKit
import simd
import UIKit

/// PencilKit's side of feedback: a drawing's strokes as `FeedbackStroke`s, and its ink as
/// pictures in true colors. Drawing units are canvas units (`MarkupCanvas` keeps them so).
/// Nonisolated: `FeedbackDraft` draws the pictures off the main actor, as PencilKit's sample
/// code draws its thumbnails, never on the main thread beside the live canvas.
nonisolated enum FeedbackInk {
    /// The visible parts of `drawing`'s strokes, each with the zoom it was drawn at (`zooms`,
    /// by stroke path creation date; 1 when unknown).
    static func strokes(of drawing: PKDrawing, zooms: [Date: CGFloat]) -> [FeedbackStroke] {
        var result: [FeedbackStroke] = []
        for stroke in drawing.strokes {
            let t = stroke.transform
            let scale = Float(abs(t.a * t.d - t.b * t.c).squareRoot())
            let date = stroke.path.creationDate
            let ink = name(of: stroke.ink.inkType), color = hex(stroke.ink.color)
            let zoom = Float(zooms[date] ?? 1)
            // A stroke the pixel eraser cut keeps only these stretches of its path.
            let ranges: [ClosedRange<CGFloat>?] = stroke.mask == nil ? [nil] : stroke.maskedPathRanges.map { Optional($0) }
            for range in ranges {
                var points: [SIMD2<Float>] = []
                var widths: Float = 0
                for point in stroke.path.interpolatedPoints(in: range, by: .distance(2)) {
                    let p = point.location.applying(t)
                    points.append(SIMD2(Float(p.x), Float(p.y)))
                    widths += Float(point.size.width) * scale
                }
                guard !points.isEmpty else { continue }
                result.append(FeedbackStroke(
                    points: points, width: max(widths / Float(points.count), 0.5), ink: ink, color: color, zoom: zoom, date: date))
            }
        }
        return result
    }

    /// The ink of `drawing` over `rect` (canvas units) at `scale` pixels per unit, transparent
    /// elsewhere. PencilKit adapts ink to dark mode; this draws the colors the painter picked.
    static func image(of drawing: PKDrawing, rect: CGRect, scale: CGFloat) -> CGImage? {
        guard rect.width > 0, rect.height > 0, scale > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image?.cgImage
    }

    /// "pen", "marker", "pencil", … from PencilKit's "com.apple.ink.pen".
    static func name(of type: PKInk.InkType) -> String {
        type.rawValue.split(separator: ".").last.map(String.init) ?? type.rawValue
    }

    /// `#RRGGBB` in sRGB (light appearance).
    static func hex(_ color: UIColor) -> String {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
