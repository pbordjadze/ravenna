import CoreGraphics
import PaintCore

// What Refine's geometry (PaintCore's `RefineGeometry`, `RefineGestures`) needs on screen alone.

extension PenPath {
    /// The path drawn on screen for `points`, the same curves `smoothed` samples.
    nonisolated static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            path.addLine(to: points.last ?? first)
            return path
        }
        for k in 1..<(points.count - 1) {
            let end = k == points.count - 2 ? points[k + 1] : midpoint(points[k], points[k + 1])
            path.addQuadCurve(to: end, control: points[k])
        }
        return path
    }
}

extension LineChains {
    /// The chains of the drawing Refine shows.
    nonisolated init(_ drawing: LineArtDrawing) { self.init(lines: drawing.lines.map(\.points)) }
}

extension RefineShape {
    nonisolated var systemImage: String {
        switch self {
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .oval: "oval"
        case .curve: "point.topleft.down.to.point.bottomright.curvepath"
        case .polygon: "hexagon"
        case .star: "star"
        }
    }
}
