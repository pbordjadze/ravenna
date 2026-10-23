// Copied from Paint by Moonlight (pbordjadze/paint-by-number, Sources/PaintCore/Vector/Earcut.swift at
// the pinned revision; there internal), a port of mapbox/earcut 3.0 (ISC, © 2016 Mapbox:
// ACKNOWLEDGEMENTS.md).

/// Polygon triangulation by ear clipping with hole elimination — a faithful port of
/// mapbox/earcut 3.0 (ISC license, © Mapbox): z-order hashing for large polygons,
/// filtering of collinear/duplicate points, local self-intersection curing and a last
/// resort polygon split, so it degrades gracefully on touching or degenerate rings.
///
/// Nodes live in flat arrays and the struct is reusable, so triangulating many small
/// regions does not allocate per polygon.
struct Earcut {
    private var xs: [Double] = [], ys: [Double] = []
    private var index: [Int32] = []
    private var prevNode: [Int32] = [], nextNode: [Int32] = []
    private var prevZ: [Int32] = [], nextZ: [Int32] = []
    private var zValue: [Int32] = []
    private var steiner: [Bool] = []

    private var minX = 0.0, minY = 0.0, invSize = 0.0

    /// Triangulates `points[0..<holeStarts.first]` (outer ring) with holes starting at each
    /// of `holeStarts`. Appends triangles as indices into `points`, oriented like the outer
    /// ring in earcut's convention (positive shoelace area).
    mutating func triangulate(_ points: [SIMD2<Double>], holeStarts: [Int], into triangles: inout [UInt32]) {
        reset(capacity: points.count + 2 * holeStarts.count + 8)
        let outerLen = holeStarts.first ?? points.count
        var outer = linkedList(points, 0, outerLen, clockwise: true)
        guard outer >= 0, nextNode[outer] != prevNode[outer] else { return }
        if !holeStarts.isEmpty { outer = eliminateHoles(points, holeStarts, outer) }

        invSize = 0
        if points.count > 80 {
            minX = points[0].x; minY = points[0].y
            var maxX = minX, maxY = minY
            for i in 1..<outerLen {
                let p = points[i]
                if p.x < minX { minX = p.x }
                if p.y < minY { minY = p.y }
                if p.x > maxX { maxX = p.x }
                if p.y > maxY { maxY = p.y }
            }
            let size = max(maxX - minX, maxY - minY)
            invSize = size != 0 ? 32767 / size : 0
        }
        earcutLinked(outer, &triangles, pass: 0)
    }

    private mutating func reset(capacity: Int) {
        xs.removeAll(keepingCapacity: true); ys.removeAll(keepingCapacity: true)
        index.removeAll(keepingCapacity: true)
        prevNode.removeAll(keepingCapacity: true); nextNode.removeAll(keepingCapacity: true)
        prevZ.removeAll(keepingCapacity: true); nextZ.removeAll(keepingCapacity: true)
        zValue.removeAll(keepingCapacity: true); steiner.removeAll(keepingCapacity: true)
        xs.reserveCapacity(capacity); ys.reserveCapacity(capacity); index.reserveCapacity(capacity)
        prevNode.reserveCapacity(capacity); nextNode.reserveCapacity(capacity)
        prevZ.reserveCapacity(capacity); nextZ.reserveCapacity(capacity)
        zValue.reserveCapacity(capacity); steiner.reserveCapacity(capacity)
    }

    // MARK: - Linked list

    private mutating func createNode(_ i: Int, _ x: Double, _ y: Double) -> Int {
        xs.append(x); ys.append(y); index.append(Int32(i))
        prevNode.append(-1); nextNode.append(-1); prevZ.append(-1); nextZ.append(-1)
        zValue.append(0); steiner.append(false)
        return xs.count - 1
    }

    private mutating func insertNode(_ i: Int, _ x: Double, _ y: Double, _ last: Int) -> Int {
        let p = createNode(i, x, y)
        if last < 0 {
            prevNode[p] = Int32(p); nextNode[p] = Int32(p)
        } else {
            let ln = Int(nextNode[last])
            nextNode[p] = Int32(ln); prevNode[p] = Int32(last)
            prevNode[ln] = Int32(p); nextNode[last] = Int32(p)
        }
        return p
    }

    private mutating func removeNode(_ p: Int) {
        let n = Int(nextNode[p]), pr = Int(prevNode[p])
        prevNode[n] = Int32(pr); nextNode[pr] = Int32(n)
        let pz = Int(prevZ[p]), nz = Int(nextZ[p])
        if pz >= 0 { nextZ[pz] = Int32(nz) }
        if nz >= 0 { prevZ[nz] = Int32(pz) }
    }

    @inline(__always) private func next(_ p: Int) -> Int { Int(nextNode[p]) }
    @inline(__always) private func prev(_ p: Int) -> Int { Int(prevNode[p]) }

    private mutating func linkedList(_ pts: [SIMD2<Double>], _ start: Int, _ end: Int, clockwise: Bool) -> Int {
        guard start < end else { return -1 }
        var last = -1
        if clockwise == (Earcut.signedArea(pts, start, end) > 0) {
            for i in start..<end { last = insertNode(i, pts[i].x, pts[i].y, last) }
        } else {
            for i in stride(from: end - 1, through: start, by: -1) { last = insertNode(i, pts[i].x, pts[i].y, last) }
        }
        if last >= 0 && equals(last, next(last)) {
            removeNode(last)
            last = next(last)
        }
        return last
    }

    private static func signedArea(_ pts: [SIMD2<Double>], _ start: Int, _ end: Int) -> Double {
        var sum = 0.0
        var j = end - 1
        for i in start..<end {
            sum += (pts[j].x - pts[i].x) * (pts[i].y + pts[j].y)
            j = i
        }
        return sum
    }

    /// Eliminates collinear or duplicate points.
    private mutating func filterPoints(_ start: Int, _ endIn: Int = -1) -> Int {
        guard start >= 0 else { return start }
        var end = endIn < 0 ? start : endIn
        var p = start
        var again: Bool
        repeat {
            again = false
            if !steiner[p] && (equals(p, next(p)) || area(prev(p), p, next(p)) == 0) {
                removeNode(p)
                p = prev(p)
                end = p
                if p == next(p) { break }
                again = true
            } else {
                p = next(p)
            }
        } while again || p != end
        return end
    }

    // MARK: - Ear slicing

    private mutating func earcutLinked(_ earIn: Int, _ triangles: inout [UInt32], pass: Int) {
        guard earIn >= 0 else { return }
        var ear = earIn
        if pass == 0 && invSize != 0 { indexCurve(ear) }
        var stop = ear
        while prev(ear) != next(ear) {
            let p = prev(ear), n = next(ear)
            if invSize != 0 ? isEarHashed(ear) : isEar(ear) {
                triangles.append(UInt32(index[p])); triangles.append(UInt32(index[ear])); triangles.append(UInt32(index[n]))
                removeNode(ear)
                // Skipping the next vertex leads to fewer sliver triangles.
                ear = next(n)
                stop = next(n)
                continue
            }
            ear = n
            if ear == stop {
                if pass == 0 {
                    earcutLinked(filterPoints(ear), &triangles, pass: 1)
                } else if pass == 1 {
                    let cured = cureLocalIntersections(filterPoints(ear), &triangles)
                    earcutLinked(cured, &triangles, pass: 2)
                } else if pass == 2 {
                    splitEarcut(ear, &triangles)
                }
                break
            }
        }
    }

    private func isEar(_ ear: Int) -> Bool {
        let a = prev(ear), b = ear, c = next(ear)
        if area(a, b, c) >= 0 { return false }
        let ax = xs[a], bx = xs[b], cx = xs[c], ay = ys[a], by = ys[b], cy = ys[c]
        let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
        var p = next(c)
        while p != a {
            if xs[p] >= x0 && xs[p] <= x1 && ys[p] >= y0 && ys[p] <= y1
                && Earcut.pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, xs[p], ys[p])
                && area(prev(p), p, next(p)) >= 0 { return false }
            p = next(p)
        }
        return true
    }

    private func isEarHashed(_ ear: Int) -> Bool {
        let a = prev(ear), b = ear, c = next(ear)
        if area(a, b, c) >= 0 { return false }
        let ax = xs[a], bx = xs[b], cx = xs[c], ay = ys[a], by = ys[b], cy = ys[c]
        let x0 = min(ax, bx, cx), y0 = min(ay, by, cy), x1 = max(ax, bx, cx), y1 = max(ay, by, cy)
        let minZ = zOrder(x0, y0), maxZ = zOrder(x1, y1)

        @inline(__always) func blocks(_ p: Int) -> Bool {
            xs[p] >= x0 && xs[p] <= x1 && ys[p] >= y0 && ys[p] <= y1 && p != a && p != c
                && Earcut.pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, xs[p], ys[p])
                && area(prev(p), p, next(p)) >= 0
        }

        var p = Int(prevZ[ear]), n = Int(nextZ[ear])
        while p >= 0 && zValue[p] >= minZ && n >= 0 && zValue[n] <= maxZ {
            if blocks(p) { return false }
            p = Int(prevZ[p])
            if blocks(n) { return false }
            n = Int(nextZ[n])
        }
        while p >= 0 && zValue[p] >= minZ {
            if blocks(p) { return false }
            p = Int(prevZ[p])
        }
        while n >= 0 && zValue[n] <= maxZ {
            if blocks(n) { return false }
            n = Int(nextZ[n])
        }
        return true
    }

    /// Cures small local self-intersections.
    private mutating func cureLocalIntersections(_ startIn: Int, _ triangles: inout [UInt32]) -> Int {
        guard startIn >= 0 else { return startIn }
        var start = startIn
        var p = start
        repeat {
            let a = prev(p), b = next(next(p))
            if !equals(a, b) && intersects(a, p, next(p), b) && locallyInside(a, b) && locallyInside(b, a) {
                triangles.append(UInt32(index[a])); triangles.append(UInt32(index[p])); triangles.append(UInt32(index[b]))
                removeNode(p)
                removeNode(next(p))
                p = b
                start = b
            }
            p = next(p)
        } while p != start
        return filterPoints(p)
    }

    /// Splits the polygon along a valid diagonal and triangulates both halves.
    private mutating func splitEarcut(_ start: Int, _ triangles: inout [UInt32]) {
        var a = start
        repeat {
            var b = next(next(a))
            while b != prev(a) {
                if index[a] != index[b] && isValidDiagonal(a, b) {
                    var c = splitPolygon(a, b)
                    let a2 = filterPoints(a, next(a))
                    c = filterPoints(c, next(c))
                    earcutLinked(a2, &triangles, pass: 0)
                    earcutLinked(c, &triangles, pass: 0)
                    return
                }
                b = next(b)
            }
            a = next(a)
        } while a != start
    }

    // MARK: - Holes

    private mutating func eliminateHoles(_ pts: [SIMD2<Double>], _ holeStarts: [Int], _ outerIn: Int) -> Int {
        var queue: [Int] = []
        for (i, start) in holeStarts.enumerated() {
            let end = i < holeStarts.count - 1 ? holeStarts[i + 1] : pts.count
            let list = linkedList(pts, start, end, clockwise: false)
            guard list >= 0 else { continue }
            if list == next(list) { steiner[list] = true }
            queue.append(getLeftmost(list))
        }
        queue.sort { compareXYSlope($0, $1) }
        var outer = outerIn
        for hole in queue { outer = eliminateHole(hole, outer) }
        return outer
    }

    private func compareXYSlope(_ a: Int, _ b: Int) -> Bool {
        if xs[a] != xs[b] { return xs[a] < xs[b] }
        if ys[a] != ys[b] { return ys[a] < ys[b] }
        // Holes whose leftmost points coincide: order counter-clockwise so the bridge found
        // for each is the point where they meet.
        let an = next(a), bn = next(b)
        let aSlope = (ys[an] - ys[a]) / (xs[an] - xs[a])
        let bSlope = (ys[bn] - ys[b]) / (xs[bn] - xs[b])
        return aSlope < bSlope
    }

    private mutating func eliminateHole(_ hole: Int, _ outer: Int) -> Int {
        let bridge = findHoleBridge(hole, outer)
        guard bridge >= 0 else { return outer }
        let bridgeReverse = splitPolygon(bridge, hole)
        _ = filterPoints(bridgeReverse, next(bridgeReverse))
        return filterPoints(bridge, next(bridge))
    }

    /// David Eberly's algorithm for finding a bridge between a hole and the outer polygon.
    private func findHoleBridge(_ hole: Int, _ outer: Int) -> Int {
        var p = outer
        let hx = xs[hole], hy = ys[hole]
        var qx = -Double.infinity
        var m = -1
        if equals(hole, p) { return p }
        repeat {
            let pn = next(p)
            if equals(hole, pn) { return pn }
            if hy <= ys[p] && hy >= ys[pn] && ys[pn] != ys[p] {
                let x = xs[p] + (hy - ys[p]) * (xs[pn] - xs[p]) / (ys[pn] - ys[p])
                if x <= hx && x > qx {
                    qx = x
                    m = xs[p] < xs[pn] ? p : pn
                    if x == hx { return m }  // hole touches outer segment; pick leftmost endpoint
                }
            }
            p = pn
        } while p != outer
        guard m >= 0 else { return -1 }

        // Look for points inside the triangle of hole point, segment intersection and
        // endpoint; if any, connect to the one with the minimum angle to the ray.
        let stop = m
        let mx = xs[m], my = ys[m]
        var tanMin = Double.infinity
        p = m
        repeat {
            if hx >= xs[p] && xs[p] >= mx && hx != xs[p]
                && Earcut.pointInTriangle(hy < my ? hx : qx, hy, mx, my, hy < my ? qx : hx, hy, xs[p], ys[p]) {
                let tan = abs(hy - ys[p]) / (hx - xs[p])
                if locallyInside(p, hole)
                    && (tan < tanMin || (tan == tanMin && (xs[p] > xs[m] || (xs[p] == xs[m] && sectorContainsSector(m, p))))) {
                    m = p
                    tanMin = tan
                }
            }
            p = next(p)
        } while p != stop
        return m
    }

    private func sectorContainsSector(_ m: Int, _ p: Int) -> Bool {
        area(prev(m), m, prev(p)) < 0 && area(next(p), m, next(m)) < 0
    }

    private func getLeftmost(_ start: Int) -> Int {
        var p = start, leftmost = start
        repeat {
            if xs[p] < xs[leftmost] || (xs[p] == xs[leftmost] && ys[p] < ys[leftmost]) { leftmost = p }
            p = next(p)
        } while p != start
        return leftmost
    }

    // MARK: - Z-order

    private func zOrder(_ x: Double, _ y: Double) -> Int32 {
        var ix = Int32(truncatingIfNeeded: Int((x - minX) * invSize))
        var iy = Int32(truncatingIfNeeded: Int((y - minY) * invSize))
        ix = (ix | (ix << 8)) & 0x00FF_00FF
        ix = (ix | (ix << 4)) & 0x0F0F_0F0F
        ix = (ix | (ix << 2)) & 0x3333_3333
        ix = (ix | (ix << 1)) & 0x5555_5555
        iy = (iy | (iy << 8)) & 0x00FF_00FF
        iy = (iy | (iy << 4)) & 0x0F0F_0F0F
        iy = (iy | (iy << 2)) & 0x3333_3333
        iy = (iy | (iy << 1)) & 0x5555_5555
        return ix | (iy << 1)
    }

    private mutating func indexCurve(_ start: Int) {
        var p = start
        repeat {
            if zValue[p] == 0 { zValue[p] = zOrder(xs[p], ys[p]) }
            prevZ[p] = prevNode[p]
            nextZ[p] = nextNode[p]
            p = next(p)
        } while p != start
        let pz = Int(prevZ[p])
        nextZ[pz] = -1
        prevZ[p] = -1
        sortLinked(p)
    }

    /// Simon Tatham's linked list merge sort.
    private mutating func sortLinked(_ listIn: Int) {
        var list = listIn
        var inSize = 1
        var numMerges: Int
        repeat {
            var p = list
            list = -1
            var tail = -1
            numMerges = 0
            while p >= 0 {
                numMerges += 1
                var q = p
                var pSize = 0
                for _ in 0..<inSize {
                    pSize += 1
                    q = Int(nextZ[q])
                    if q < 0 { break }
                }
                var qSize = inSize
                while pSize > 0 || (qSize > 0 && q >= 0) {
                    let e: Int
                    if pSize != 0 && (qSize == 0 || q < 0 || zValue[p] <= zValue[q]) {
                        e = p
                        p = Int(nextZ[p])
                        pSize -= 1
                    } else {
                        e = q
                        q = Int(nextZ[q])
                        qSize -= 1
                    }
                    if tail >= 0 { nextZ[tail] = Int32(e) } else { list = e }
                    prevZ[e] = Int32(tail)
                    tail = e
                }
                p = q
            }
            nextZ[tail] = -1
            inSize *= 2
        } while numMerges > 1
    }

    // MARK: - Geometry predicates

    @inline(__always)
    private static func pointInTriangle(
        _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ px: Double, _ py: Double
    ) -> Bool {
        (cx - px) * (ay - py) >= (ax - px) * (cy - py)
            && (ax - px) * (by - py) >= (bx - px) * (ay - py)
            && (bx - px) * (cy - py) >= (cx - px) * (by - py)
    }

    @inline(__always)
    private static func pointInTriangleExceptFirst(
        _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double, _ px: Double, _ py: Double
    ) -> Bool {
        !(ax == px && ay == py) && pointInTriangle(ax, ay, bx, by, cx, cy, px, py)
    }

    private func isValidDiagonal(_ a: Int, _ b: Int) -> Bool {
        index[next(a)] != index[b] && index[prev(a)] != index[b] && !intersectsPolygon(a, b)
            && ((locallyInside(a, b) && locallyInside(b, a) && middleInside(a, b)
                && (area(prev(a), a, prev(b)) != 0 || area(a, prev(b), b) != 0))
                || (equals(a, b) && area(prev(a), a, next(a)) > 0 && area(prev(b), b, next(b)) > 0))
    }

    /// Signed area of a triangle (earcut's sign convention: negative for a convex ear).
    @inline(__always)
    private func area(_ p: Int, _ q: Int, _ r: Int) -> Double {
        (ys[q] - ys[p]) * (xs[r] - xs[q]) - (xs[q] - xs[p]) * (ys[r] - ys[q])
    }

    @inline(__always)
    private func equals(_ a: Int, _ b: Int) -> Bool { xs[a] == xs[b] && ys[a] == ys[b] }

    @inline(__always)
    private static func sign(_ v: Double) -> Int { v > 0 ? 1 : (v < 0 ? -1 : 0) }

    private func onSegment(_ p: Int, _ q: Int, _ r: Int) -> Bool {
        xs[q] <= max(xs[p], xs[r]) && xs[q] >= min(xs[p], xs[r]) && ys[q] <= max(ys[p], ys[r]) && ys[q] >= min(ys[p], ys[r])
    }

    private func intersects(_ p1: Int, _ q1: Int, _ p2: Int, _ q2: Int) -> Bool {
        let o1 = Earcut.sign(area(p1, q1, p2)), o2 = Earcut.sign(area(p1, q1, q2))
        let o3 = Earcut.sign(area(p2, q2, p1)), o4 = Earcut.sign(area(p2, q2, q1))
        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p1, p2, q1) { return true }
        if o2 == 0 && onSegment(p1, q2, q1) { return true }
        if o3 == 0 && onSegment(p2, p1, q2) { return true }
        if o4 == 0 && onSegment(p2, q1, q2) { return true }
        return false
    }

    private func intersectsPolygon(_ a: Int, _ b: Int) -> Bool {
        var p = a
        repeat {
            let pn = next(p)
            if index[p] != index[a] && index[pn] != index[a] && index[p] != index[b] && index[pn] != index[b]
                && intersects(p, pn, a, b) { return true }
            p = pn
        } while p != a
        return false
    }

    private func locallyInside(_ a: Int, _ b: Int) -> Bool {
        area(prev(a), a, next(a)) < 0
            ? area(a, b, next(a)) >= 0 && area(a, prev(a), b) >= 0
            : area(a, b, prev(a)) < 0 || area(a, next(a), b) < 0
    }

    private func middleInside(_ a: Int, _ b: Int) -> Bool {
        var p = a
        var inside = false
        let px = (xs[a] + xs[b]) / 2, py = (ys[a] + ys[b]) / 2
        repeat {
            let pn = next(p)
            if (ys[p] > py) != (ys[pn] > py) && ys[pn] != ys[p]
                && px < (xs[pn] - xs[p]) * (py - ys[p]) / (ys[pn] - ys[p]) + xs[p] {
                inside.toggle()
            }
            p = pn
        } while p != a
        return inside
    }

    /// Links two vertices with a bridge: splits a ring in two, or merges a hole into the outer ring.
    private mutating func splitPolygon(_ a: Int, _ b: Int) -> Int {
        let a2 = createNode(Int(index[a]), xs[a], ys[a])
        let b2 = createNode(Int(index[b]), xs[b], ys[b])
        let an = next(a), bp = prev(b)
        nextNode[a] = Int32(b); prevNode[b] = Int32(a)
        nextNode[a2] = Int32(an); prevNode[an] = Int32(a2)
        nextNode[b2] = Int32(a2); prevNode[a2] = Int32(b2)
        nextNode[bp] = Int32(b2); prevNode[b2] = Int32(bp)
        return b2
    }
}
