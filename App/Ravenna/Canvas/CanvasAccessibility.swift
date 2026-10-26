import CoreGraphics
import Foundation
import PaintCore
import UIKit
import simd

/// Where an area sits on the canvas, in thirds ("top left" … "bottom right"), so VoiceOver
/// users know where on the picture they are.
nonisolated enum CanvasPosition: Int, Sendable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    /// Column = clamp(floor(3·x / width), 0, 2), rows alike; non-finite input maps to the middle.
    init(_ p: SIMD2<Float>, width: Int, height: Int) {
        func third(_ v: Float, _ extent: Int) -> Int {
            let t = 3 * v / Float(max(extent, 1))
            guard t.isFinite else { return 1 }
            return min(max(Int(t.rounded(.down)), 0), 2)
        }
        self = CanvasPosition(rawValue: third(p.y, height) * 3 + third(p.x, width)) ?? .center
    }

    var spoken: String {
        switch self {
        case .topLeft: String(localized: "paint.position.topLeft", defaultValue: "top left", comment: "Where an area sits on the painting")
        case .top: String(localized: "paint.position.top", defaultValue: "top", comment: "Where an area sits on the painting")
        case .topRight: String(localized: "paint.position.topRight", defaultValue: "top right", comment: "Where an area sits on the painting")
        case .left: String(localized: "paint.position.left", defaultValue: "left", comment: "Where an area sits on the painting")
        case .center: String(localized: "paint.position.center", defaultValue: "center", comment: "Where an area sits on the painting")
        case .right: String(localized: "paint.position.right", defaultValue: "right", comment: "Where an area sits on the painting")
        case .bottomLeft: String(localized: "paint.position.bottomLeft", defaultValue: "bottom left", comment: "Where an area sits on the painting")
        case .bottom: String(localized: "paint.position.bottom", defaultValue: "bottom", comment: "Where an area sits on the painting")
        case .bottomRight: String(localized: "paint.position.bottomRight", defaultValue: "bottom right", comment: "Where an area sits on the painting")
        }
    }
}

/// Which unpainted areas VoiceOver offers, and in what order. Pure; `CanvasView` supplies the
/// camera. Areas are identified by region index and located by their anchor (the number).
nonisolated enum CanvasAccessibility {
    /// At most this many areas are exposed at once: enough to explore what is on screen,
    /// few enough that swiping through them stays quick.
    static let limit = 40

    /// Reading order: rows of `rowHeight` top to bottom, then left to right.
    nonisolated struct ReadingKey: Comparable, Sendable {
        var row: Int
        var x: Float
        var region: Int

        static func < (a: Self, b: Self) -> Bool {
            (a.row, a.x, a.region) < (b.row, b.x, b.region)
        }
    }

    static func key(_ region: Int, anchor: SIMD2<Float>, rowHeight: Float) -> ReadingKey {
        let row = anchor.y / max(rowHeight, 1e-3)
        return ReadingKey(row: row.isFinite ? Int(row.rounded(.down)) : 0, x: anchor.x, region: region)
    }

    /// Regions whose anchor lies in `visible` (canvas units, edges included): the `limit`
    /// nearest `center` (ties: lower index), in reading order.
    static func visibleAreas(
        _ regions: [Int], anchors: [SIMD2<Float>], visible: CGRect, center: SIMD2<Float>, rowHeight: Float
    ) -> [Int] {
        let inside = regions.filter { r in
            let a = anchors[r]
            return CGFloat(a.x) >= visible.minX && CGFloat(a.x) <= visible.maxX
                && CGFloat(a.y) >= visible.minY && CGFloat(a.y) <= visible.maxY
        }
        let nearest = inside
            .map { (distance: simd_distance_squared(anchors[$0], center), region: $0) }
            .sorted { ($0.distance, $0.region) < ($1.distance, $1.region) }
            .prefix(limit)
            .map { $0.region }
        return nearest.sorted { key($0, anchor: anchors[$0], rowHeight: rowHeight) < key($1, anchor: anchors[$1], rowHeight: rowHeight) }
    }

    /// The area after `key` in reading order over `regions`, wrapping to the first; nil when
    /// `regions` is empty.
    static func next(after key: ReadingKey?, in regions: [Int], anchors: [SIMD2<Float>], rowHeight: Float) -> Int? {
        let keys = regions.map { Self.key($0, anchor: anchors[$0], rowHeight: rowHeight) }
        guard let first = keys.min() else { return nil }
        guard let key else { return first.region }
        return (keys.filter { $0 > key }.min() ?? first).region
    }

    /// How far a VoiceOver page scroll moves the content offset for a page of `page`.
    /// Directions name the three-finger swipe and act like dragging: swiping up brings what
    /// is below into view. Next and previous page vertically.
    static func pageStep(_ direction: UIAccessibilityScrollDirection, page: CGSize) -> CGVector? {
        switch direction {
        case .up, .next: return CGVector(dx: 0, dy: page.height)
        case .down, .previous: return CGVector(dx: 0, dy: -page.height)
        case .left: return CGVector(dx: page.width, dy: 0)
        case .right: return CGVector(dx: -page.width, dy: 0)
        @unknown default: return nil
        }
    }

    /// The region whose anchor is nearest `point` (ties: lower index).
    static func nearest(_ regions: [Int], anchors: [SIMD2<Float>], to point: SIMD2<Float>) -> Int? {
        regions.min { a, b in
            (simd_distance_squared(anchors[a], point), a) < (simd_distance_squared(anchors[b], point), b)
        }
    }
}

/// One unpainted area on the canvas for VoiceOver and Switch Control: activating it paints
/// the area with the selected color.
final class CanvasAreaElement: UIAccessibilityElement {
    let region: Int

    init(region: Int, container: CanvasView) {
        self.region = region
        super.init(accessibilityContainer: container)
    }

    override func accessibilityActivate() -> Bool {
        (accessibilityContainer as? CanvasView)?.paintForAccessibility(region) ?? false
    }
}
