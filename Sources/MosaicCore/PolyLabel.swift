// Copied from Paint by Moonlight (pbordjadze/paint-by-number, Sources/PaintCore/Vector/PolyLabel.swift
// at the pinned revision; there internal), a port of mapbox/polylabel (ISC, © 2016 Mapbox:
// ACKNOWLEDGEMENTS.md), without its keep-out search, which Ravenna has no use for.

/// A polygon with holes as one flat point list: ring `k` is
/// `points[ringStarts[k]..<ringStarts[k + 1]]` (implicitly closed).
struct FlatPolygon {
    var points: [SIMD2<Double>] = []
    var ringStarts: [Int] = [0]

    var ringCount: Int { ringStarts.count - 1 }

    mutating func removeAll() {
        points.removeAll(keepingCapacity: true)
        ringStarts.removeAll(keepingCapacity: true)
        ringStarts.append(0)
    }

    mutating func closeRing() { ringStarts.append(points.count) }

    /// Twice the signed shoelace area of ring k.
    func area2(ring k: Int) -> Double {
        let a = ringStarts[k], b = ringStarts[k + 1]
        guard b - a >= 3 else { return 0 }
        var sum = 0.0
        var j = b - 1
        for i in a..<b {
            sum += points[j].x * points[i].y - points[i].x * points[j].y
            j = i
        }
        return sum
    }

    /// Signed distance from (x, y) to the outline: positive inside (even-odd over all rings).
    func signedDistance(_ x: Double, _ y: Double) -> Double {
        var inside = false
        var minDistSq = Double.infinity
        for k in 0..<ringCount {
            let a = ringStarts[k], b = ringStarts[k + 1]
            guard b > a else { continue }
            var j = b - 1
            for i in a..<b {
                let pa = points[i], pb = points[j]
                if (pa.y > y) != (pb.y > y) && x < (pb.x - pa.x) * (y - pa.y) / (pb.y - pa.y) + pa.x {
                    inside.toggle()
                }
                minDistSq = min(minDistSq, FlatPolygon.segmentDistanceSquared(x, y, pa, pb))
                j = i
            }
        }
        guard minDistSq.isFinite else { return 0 }
        return (inside ? 1 : -1) * minDistSq.squareRoot()
    }

    @inline(__always)
    static func segmentDistanceSquared(_ px: Double, _ py: Double, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        var x = a.x, y = a.y
        var dx = b.x - x, dy = b.y - y
        if dx != 0 || dy != 0 {
            let t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy)
            if t > 1 {
                x = b.x; y = b.y
            } else if t > 0 {
                x += dx * t; y += dy * t
            }
        }
        dx = px - x
        dy = py - y
        return dx * dx + dy * dy
    }
}

/// The part of a polygon's outline that matters within a small box around an interior
/// point: every segment that can be the nearest one to some point of the box, and every
/// segment that can cross the line from the box centre to such a point — so distances
/// are exact and inside/outside follows from crossing parity relative to the centre.
struct LocalOutline {
    let origin: SIMD2<Double>
    let halfSize: Double
    private var a: [SIMD2<Double>] = [], b: [SIMD2<Double>] = []

    /// Nil when `origin` is not strictly inside the polygon.
    init?(_ poly: FlatPolygon, around origin: SIMD2<Double>, halfSize: Double) {
        let d0 = poly.signedDistance(origin.x, origin.y)
        guard d0 > 0 else { return nil }
        self.origin = origin
        self.halfSize = halfSize
        // A box point q is within halfSize·√2 of the origin, so its nearest outline point is
        // within d0 + 2·halfSize·√2 of the origin.
        let reach = d0 + 2 * halfSize * 2.0.squareRoot() + 0.5
        let lo = origin - reach, hi = origin + reach
        for k in 0..<poly.ringCount {
            let s = poly.ringStarts[k], e = poly.ringStarts[k + 1]
            guard e > s else { continue }
            var j = e - 1
            for i in s..<e {
                let p = poly.points[j], q = poly.points[i]
                if max(p.x, q.x) >= lo.x && min(p.x, q.x) <= hi.x && max(p.y, q.y) >= lo.y && min(p.y, q.y) <= hi.y {
                    a.append(p); b.append(q)
                }
                j = i
            }
        }
    }

    func signedDistance(_ x: Double, _ y: Double) -> Double {
        let q = SIMD2(x, y)
        var minDistSq = Double.infinity
        var outside = false
        @inline(__always) func orient(_ p: SIMD2<Double>, _ r: SIMD2<Double>, _ t: SIMD2<Double>) -> Double {
            (r.x - p.x) * (t.y - p.y) - (r.y - p.y) * (t.x - p.x)
        }
        for i in 0..<a.count {
            minDistSq = min(minDistSq, FlatPolygon.segmentDistanceSquared(x, y, a[i], b[i]))
            // Half-open side test keeps crossings through vertices counted exactly once.
            if (orient(origin, q, a[i]) > 0) != (orient(origin, q, b[i]) > 0)
                && (orient(a[i], b[i], origin) > 0) != (orient(a[i], b[i], q) > 0) {
                outside.toggle()
            }
        }
        guard minDistSq.isFinite else { return 0 }
        return (outside ? -1 : 1) * minDistSq.squareRoot()
    }
}

/// Pole of inaccessibility — the interior point farthest from the outline — after
/// mapbox/polylabel (ISC license): best-first quadtree search that prunes cells which
/// cannot beat the best distance found so far by more than `precision`.
enum PolyLabel {
    private struct Cell {
        var x: Double, y: Double, h: Double, d: Double
        var max: Double { d + h * 2.0.squareRoot() }
    }

    /// Above this many vertices, search only near the seed (see `find`).
    static let localSearchThreshold = 64

    /// Returns the pole and its distance to the outline. `seed` (a raster distance
    /// transform maximum) primes the search so most cells are pruned immediately. For large
    /// polygons the search is confined to a few units around the seed — the smoothed
    /// polygon's pole lies next to the raster one — and only boundary segments that can be
    /// nearest to that neighbourhood are consulted, so the cost no longer scales with the
    /// number of vertices (big regions with thousands of holes).
    ///
    /// The seed itself is always evaluated (exactly, in both paths), so the returned distance
    /// is at least the seed's: `EdgeSmoother`'s label room guarantee relies on it.
    static func find(_ poly: FlatPolygon, precision: Double, seed: SIMD2<Double>) -> (position: SIMD2<Double>, distance: Double) {
        if poly.points.count > localSearchThreshold, let local = LocalOutline(poly, around: seed, halfSize: 3) {
            let h = local.halfSize
            return search(minX: seed.x - h, minY: seed.y - h, maxX: seed.x + h, maxY: seed.y + h, precision: precision, seed: seed) {
                local.signedDistance($0, $1)
            }
        }
        let outerEnd = poly.ringStarts.count > 1 ? poly.ringStarts[1] : 0
        guard outerEnd > 0 else { return (seed, 0) }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for i in 0..<outerEnd {
            let p = poly.points[i]
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return search(minX: minX, minY: minY, maxX: maxX, maxY: maxY, precision: precision, seed: seed) {
            poly.signedDistance($0, $1)
        }
    }

    /// Best-first search over the box for the maximum of `distance`.
    private static func search(
        minX: Double, minY: Double, maxX: Double, maxY: Double, precision: Double, seed: SIMD2<Double>,
        distance: (Double, Double) -> Double
    ) -> (position: SIMD2<Double>, distance: Double) {
        let width = maxX - minX, height = maxY - minY
        let cellSize = max(precision, min(width, height))

        func cell(_ x: Double, _ y: Double, _ h: Double) -> Cell {
            Cell(x: x, y: y, h: h, d: distance(x, y))
        }

        var best = cell(minX + width / 2, minY + height / 2, 0)
        let s = cell(seed.x, seed.y, 0)
        if s.d > best.d { best = s }
        if cellSize == precision { return (SIMD2(best.x, best.y), max(0, best.d)) }

        var heap: [Cell] = []
        func push(_ c: Cell) {
            heap.append(c)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if heap[parent].max >= heap[i].max { break }
                heap.swapAt(parent, i)
                i = parent
            }
        }
        func pop() -> Cell {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < heap.count && heap[l].max > heap[m].max { m = l }
                    if r < heap.count && heap[r].max > heap[m].max { m = r }
                    if m == i { break }
                    heap.swapAt(i, m)
                    i = m
                }
            }
            return top
        }
        func consider(_ x: Double, _ y: Double, _ h: Double) {
            let c = cell(x, y, h)
            if c.max > best.d + precision { push(c) }
            if c.d > best.d { best = c }
        }

        var h = cellSize / 2
        var x = minX
        while x < maxX {
            var y = minY
            while y < maxY {
                consider(x + h, y + h, h)
                y += cellSize
            }
            x += cellSize
        }
        while !heap.isEmpty {
            let c = pop()
            if c.max - best.d <= precision { break }
            h = c.h / 2
            consider(c.x - h, c.y - h, h)
            consider(c.x + h, c.y - h, h)
            consider(c.x - h, c.y + h, h)
            consider(c.x + h, c.y + h, h)
        }
        return (SIMD2(best.x, best.y), max(0, best.d))
    }
}
