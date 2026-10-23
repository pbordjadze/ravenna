import MosaicKit
import PaintCore

extension MosaicCore {
    public enum TemplateError: Error, Equatable {
        case noTiles
        /// A tile with no area once its corners are on PaintCore's coordinate grid.
        case degenerateTile(Int)
    }

    /// The canvas long side templates are built at: PaintCore's own range (its working image's long
    /// side is 1100 to 2100 units), where nearly every tile has room for its number (issue #2).
    public static let templateLongSide = 2048
    /// The most a template's canvas grows to give its smallest tile room.
    public static let maximumLongSide = 4096

    /// A mosaic as a PaintCore template that `Template.validate` passes: region `i` is tile `i` in
    /// paint `tile.paint`, and the last region is the grout, every joint at once, in a paint of its own
    /// (the last palette entry, `mosaic.grout`), painted as one area (issue #6).
    ///
    /// Built directly, not re-traced: each tile's outline is its corners (on
    /// `Template.coordinateQuantum`), one closed edge with the grout beyond it, and the grout is the
    /// canvas with every tile as a hole. Two things the engine makes need more:
    /// - A tile laid over another and inside it (a pupil over its iris) is a hole in that tile, its
    ///   edge shared with it rather than the grout.
    /// - An outline that crosses or touches itself (the engine's simplified tracings fold now and
    ///   then, about one tile in a thousand) keeps its biggest simple loop turning its own way.
    ///
    /// A tile is numbered at its pole; one too small for the usual floor (`LabelSizing.minimumRadius`,
    /// a sliver cut in the gap fill) is a detail area, read zoomed in. The grout is numbered at its
    /// roomiest spots, spread over the canvas.
    ///
    /// The canvas is `longSide` on its long side, or more when the smallest tile would be short of
    /// even a detail area's room there (the finest details' slivers), up to `maximumLongSide`.
    public static func template(of mosaic: Mosaic, longSide: Int = templateLongSide) throws -> Template {
        let n = mosaic.tiles.count
        guard n > 0, mosaic.width > 0, mosaic.height > 0 else { throw TemplateError.noTiles }
        let base = Double(longSide) / Double(max(mosaic.width, mosaic.height))
        // Each tile's room at that scale, a tile laid inside another (a pupil) a hole in it.
        let rough = mosaic.tiles.map { tile -> [SIMD2<Double>] in
            let ring = simple(tile.corners.map { SIMD2(Double($0.x), Double($0.y)) * base }, snap: { $0 }) ?? []
            return area2(ring) < 0 ? ring.reversed() : ring
        }
        let roughOutside = containers(rough)
        var roughHoles = [[Int]](repeating: [], count: n)
        for i in 0..<n { if let o = roughOutside[i] { roughHoles[o].append(i) } }
        var need = 1.0
        for (i, tile) in mosaic.tiles.enumerated() where rough[i].count >= 3 {
            var poly = FlatPolygon()
            poly.points = rough[i]
            poly.closeRing()
            for h in roughHoles[i] where rough[h].count >= 3 {
                poly.points += rough[h].reversed()
                poly.closeRing()
            }
            let room = PolyLabel.find(poly, precision: 0.005, seed: rough[i].reduce(.zero, +) / Double(rough[i].count)).distance
            let floor = Double(LabelSizing.minimumRadius(digits: LabelSizing.digitCount(colorIndex: UInt32(tile.paint)), detail: true))
            if room > 0 { need = max(need, floor / room) }
        }
        let k = base * min(need > 1 ? need * 1.05 : 1, Double(max(maximumLongSide, longSide)) / Double(longSide))
        let width = max(Int((Double(mosaic.width) * k).rounded(.up)), 1)
        let height = max(Int((Double(mosaic.height) * k).rounded(.up)), 1)
        func snap(_ p: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2(snapped(p.x, width), snapped(p.y, height))
        }

        // Each tile's ring: snapped, simple, positive (clockwise on screen).
        var outlines: [[SIMD2<Double>]] = []
        outlines.reserveCapacity(n)
        for (i, tile) in mosaic.tiles.enumerated() {
            guard var ring = simple(tile.corners.map { snap(SIMD2(Double($0.x), Double($0.y)) * k) }, snap: snap) else {
                throw TemplateError.degenerateTile(i)
            }
            if area2(ring) < 0 { ring.reverse() }
            outlines.append(ring)
        }
        let border: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(Double(width), 0), SIMD2(Double(width), Double(height)), SIMD2(0, Double(height))]
        let groutRegion = n

        // What lies beyond each tile: the tile it was laid inside, else the grout.
        let outside = containers(outlines)
        var holes = [[Int]](repeating: [], count: n + 1)
        for i in 0..<n { holes[outside[i] ?? groutRegion].append(i) }

        // Palette: the mosaic's paints, then the grout's.
        let palette = (mosaic.palette + [mosaic.grout]).map { rgb in
            PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), rgb: rgb)
        }
        let groutPaint = UInt32(mosaic.palette.count)

        // Edges: one closed edge per tile, then the border. A tile's edge runs its own way round (the
        // tile on its left) when the region beyond has the higher index, else the other way.
        var points: [SIMD2<Float>] = [], edges: [BoundaryEdge] = []
        var forwards = [Bool](repeating: true, count: n + 1)
        for (i, ring) in (outlines + [border]).enumerated() {
            let beyond = i == n ? Int(BoundaryEdge.outside) : (outside[i] ?? groutRegion)
            let ahead = i == n || i < beyond
            forwards[i] = ahead
            let run = ahead ? ring + [ring[0]] : [ring[0]] + ring.reversed()
            edges.append(BoundaryEdge(left: UInt32(ahead ? i : beyond), right: i == n ? BoundaryEdge.outside : UInt32(ahead ? beyond : i),
                                      pointStart: UInt32(points.count), pointCount: UInt32(run.count)))
            points += run.map { SIMD2<Float>($0) }
        }

        // Rings: each region's outline (a tile's, or the border for the grout), then its holes.
        var ringEdges: [EdgeRef] = [], rings: [Ring] = []
        var ringSpans: [(start: UInt32, count: UInt32)] = []
        for r in 0...n {
            let start = UInt32(rings.count)
            rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: 1, isHole: false))
            ringEdges.append(EdgeRef(edge: UInt32(r), reversed: !forwards[r]))
            for h in holes[r] {
                rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: 1, isHole: true))
                ringEdges.append(EdgeRef(edge: UInt32(h), reversed: forwards[h]))
            }
            ringSpans.append((start, UInt32(rings.count) - start))
        }

        // Each region as one polygon: its outline, then each hole reversed.
        func polygon(_ r: Int) -> FlatPolygon {
            var poly = FlatPolygon()
            poly.points = r == n ? border : outlines[r]
            poly.closeRing()
            for h in holes[r] {
                poly.points += outlines[h].reversed()
                poly.closeRing()
            }
            return poly
        }

        // Fills.
        var mesh = FillMesh()
        var earcut = Earcut()
        var fills: [(start: UInt32, count: UInt32)] = []
        var areas: [Double] = []
        for r in 0...n {
            let poly = polygon(r)
            var tri = fill(poly, &earcut)
            splitTJunctions(poly.points, &tri)
            let base = UInt32(mesh.vertices.count)
            mesh.vertices += poly.points.map { SIMD2<Float>($0) }
            mesh.vertexRegion += [UInt32](repeating: UInt32(r), count: poly.points.count)
            fills.append((UInt32(mesh.indices.count), UInt32(tri.count)))
            mesh.indices += tri.map { $0 + base }
            areas.append((0..<poly.ringCount).reduce(0.0) { $0 + poly.area2(ring: $1) } / 2)
        }

        // The region map, for hit testing: each tile's pixels by their centres, the rest grout; a
        // tile laid inside another after it, outermost first.
        var map = RegionMap(width: width, height: height, repeating: UInt32(groutRegion))
        func depth(_ i: Int) -> Int {
            var d = 0, j = i
            while let o = outside[j], d <= n { d += 1; j = o }
            return d
        }
        let depths = (0..<n).map(depth)
        for i in (0..<n).sorted(by: { depths[$0] != depths[$1] ? depths[$0] < depths[$1] : $0 < $1 }) {
            let ring = outlines[i]
            let ys = ring.map(\.y), xs = ring.map(\.x)
            let y0 = max(Int((ys.min()! - 0.5).rounded(.up)), 0), y1 = min(Int((ys.max()! - 0.5).rounded(.down)), height - 1)
            let x0 = max(Int((xs.min()! - 0.5).rounded(.up)), 0), x1 = min(Int((xs.max()! - 0.5).rounded(.down)), width - 1)
            guard y0 <= y1, x0 <= x1 else { continue }
            for y in y0...y1 {
                for x in x0...x1 where contains(ring, SIMD2(Double(x) + 0.5, Double(y) + 0.5)) {
                    map.storage[y * width + x] = UInt32(i)
                }
            }
        }

        // Labels: each tile's at its pole; the grout's at its roomiest spots, the first the roomiest.
        var labels: [Label] = [], regions: [Region] = [], detail: [UInt32] = []
        func floor(_ paint: UInt32) -> Double {
            Double(LabelSizing.minimumRadius(digits: LabelSizing.digitCount(colorIndex: paint)))
        }
        func region(_ r: Int, paint: UInt32, radius: Double, labelCount: Int) -> Region {
            let outer = r == n ? border : outlines[r]
            let xs = outer.map(\.x), ys = outer.map(\.y)
            let bounds = PixelBounds(minX: Int32(max(0, xs.min()!.rounded(.down))), minY: Int32(max(0, ys.min()!.rounded(.down))),
                                     maxX: Int32(min(Double(width), xs.max()!.rounded(.up))),
                                     maxY: Int32(min(Double(height), ys.max()!.rounded(.up))))
            return Region(colorIndex: paint, area: Float(areas[r]), bounds: bounds, inscribedRadius: Float(radius),
                          ringStart: ringSpans[r].start, ringCount: ringSpans[r].count,
                          labelStart: UInt32(labels.count), labelCount: UInt32(labelCount),
                          indexStart: fills[r].start, indexCount: fills[r].count)
        }
        for i in 0..<n {
            let centre = outlines[i].reduce(SIMD2<Double>.zero, +) / Double(outlines[i].count)
            let pole = PolyLabel.find(polygon(i), precision: 0.005, seed: centre)
            let paint = UInt32(mosaic.tiles[i].paint)
            if pole.distance < floor(paint) { detail.append(UInt32(i)) }
            regions.append(region(i, paint: paint, radius: pole.distance, labelCount: 1))
            labels.append(Label(position: SIMD2<Float>(pole.position), radius: shave(pole.distance), region: UInt32(i)))
        }
        let grout = polygon(n)
        var groutLabels: [Label] = []
        var groutRadius = 0.0
        for seed in groutSpots(map, grout: UInt32(groutRegion), spacing: Double(max(width, height)) / 16, least: floor(groutPaint)) {
            let pole = PolyLabel.find(grout, precision: 0.01, seed: seed)
            guard pole.distance > 0 else { continue }
            if groutLabels.isEmpty { groutRadius = pole.distance }
            groutLabels.append(Label(position: SIMD2<Float>(pole.position), radius: shave(pole.distance), region: UInt32(groutRegion)))
        }
        if groutRadius < floor(groutPaint) { detail.append(UInt32(groutRegion)) }
        regions.append(region(n, paint: groutPaint, radius: groutRadius, labelCount: groutLabels.count))
        labels += groutLabels

        var template = Template(width: width, height: height, colorSpace: .sRGB, palette: palette, regions: regions,
                                points: points, edges: edges, ringEdges: ringEdges, rings: rings, labels: labels,
                                mesh: mesh, regionMap: map)
        template.detailRegions = detail
        return template
    }

    /// A coordinate on `Template.coordinateQuantum`, inside the canvas.
    static func snapped(_ v: Double, _ limit: Int) -> Double {
        let q = Double(Template.coordinateQuantum)
        return min(max((v / q).rounded() * q, 0), Double(limit))
    }

    /// A label's free radius as stored: never more than measured, whatever Float makes of it.
    private static func shave(_ d: Double) -> Float { Float(d).nextDown }

    /// A region's triangles, checked. Earcut doesn't promise a correct result for every valid
    /// polygon (mapbox/earcut checks its own with `deviation`): on the Hodegetria's grout, 3,162
    /// holes on whole coordinates, its bridges crossed and its triangles overlapped by 0.5%, as
    /// upstream's own earcut.js does on the same rings. When the triangles' areas don't add up to
    /// the polygon's, it runs again on the polygon mirrored left to right, then top to bottom, then
    /// transposed, which bridge the holes another way (each mends that grout), and turns their
    /// triangles back the right way round. If none adds up, the closest stands, for
    /// `Template.validate` to judge.
    static func fill(_ poly: FlatPolygon, _ earcut: inout Earcut) -> [UInt32] {
        let holes = Array(poly.ringStarts[1..<poly.ringCount])
        let area = abs((0..<poly.ringCount).reduce(0.0) { $0 + poly.area2(ring: $1) })
        let views: [(SIMD2<Double>) -> SIMD2<Double>] = [{ $0 }, { SIMD2(-$0.x, $0.y) }, { SIMD2($0.x, -$0.y) }, { SIMD2($0.y, $0.x) }]
        var best: [UInt32] = [], bestError = Double.infinity
        for (k, view) in views.enumerated() {
            let pts = k == 0 ? poly.points : poly.points.map(view)
            var tri: [UInt32] = []
            earcut.triangulate(pts, holeStarts: holes, into: &tri)
            if k > 0 { for t in stride(from: 0, to: tri.count, by: 3) { tri.swapAt(t + 1, t + 2) } }
            var covered = 0.0
            for t in stride(from: 0, to: tri.count, by: 3) {
                let a = poly.points[Int(tri[t])], b = poly.points[Int(tri[t + 1])], c = poly.points[Int(tri[t + 2])]
                covered += abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
            }
            let error = abs(covered - area)
            if error < bestError { best = tri; bestError = error }
            if error <= 1e-9 * Swift.max(area, 1) { break }
        }
        return best
    }

    /// Twice the signed (shoelace) area of a ring: positive when clockwise on screen (y down).
    static func area2(_ ring: [SIMD2<Double>]) -> Double {
        var sum = 0.0
        var j = ring.count - 1
        for i in ring.indices {
            sum += ring[j].x * ring[i].y - ring[i].x * ring[j].y
            j = i
        }
        return sum
    }

    static func contains(_ ring: [SIMD2<Double>], _ p: SIMD2<Double>) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// The ring tidied (no repeated points, spikes or points on a straight run), and while it
    /// crosses or touches itself, cut where it first does into two loops, keeping the bigger of
    /// those turning its own way: a simple ring, or nil when nothing with area is left. Mostly
    /// inside the tile as laid; where a fold had cancelled out a lobe (winding 0), the loop kept can
    /// cover it, no more than the lobe, and `Template.validate` still catches any touch with a
    /// neighbour. Coordinates on the quantum grid keep the tests exact.
    static func simple(_ points: [SIMD2<Double>], snap: (SIMD2<Double>) -> SIMD2<Double>) -> [SIMD2<Double>]? {
        func tidy(_ p: [SIMD2<Double>]) -> [SIMD2<Double>] {
            var out: [SIMD2<Double>] = []
            for q in p where out.last != q { out.append(q) }
            while out.count > 1 && out.first == out.last { out.removeLast() }
            var changed = true
            while changed && out.count >= 3 {
                changed = false
                var i = 0
                while out.count >= 3 && i < out.count {
                    let a = out[(i + out.count - 1) % out.count], b = out[i], c = out[(i + 1) % out.count]
                    if a == b || cross(b - a, c - b) == 0 {
                        out.remove(at: i)
                        changed = true
                    } else {
                        i += 1
                    }
                }
            }
            return out
        }
        var ring = tidy(points)
        var budget = 4 * max(ring.count, 4)
        while ring.count >= 3 {
            guard let (i, j, x) = firstSelfContact(ring) else { return area2(ring) != 0 ? ring : nil }
            budget -= 1
            if budget < 0 { return nil }
            let m = ring.count, at = snap(x)
            var one: [SIMD2<Double>] = [at], two: [SIMD2<Double>] = [at]
            var q = (i + 1) % m
            while q != (j + 1) % m { one.append(ring[q]); q = (q + 1) % m }
            q = (j + 1) % m
            while q != (i + 1) % m { two.append(ring[q]); q = (q + 1) % m }
            one = tidy(one); two = tidy(two)
            // The loop turning the ring's own way and bigger: a lobe folded back the other way is
            // outside the tile as laid (winding 0), whatever its size.
            let way: Double = area2(ring) >= 0 ? 1 : -1
            let a1 = one.count >= 3 ? way * area2(one) : -.infinity, a2 = two.count >= 3 ? way * area2(two) : -.infinity
            ring = a1 >= a2 ? one : two
        }
        return nil
    }

    /// The first pair of non-adjacent sides of a ring that meet, and a point where they do.
    static func firstSelfContact(_ ring: [SIMD2<Double>]) -> (Int, Int, SIMD2<Double>)? {
        let m = ring.count
        guard m >= 4 else { return nil }
        for i in 0..<(m - 2) {
            let a = ring[i], b = ring[i + 1]
            for j in (i + 2)..<m where !(i == 0 && j == m - 1) {
                if let x = meet(a, b, ring[j], ring[(j + 1) % m]) { return (i, j, x) }
            }
        }
        return nil
    }

    /// Where segments ab and cd meet (crossing, touching or overlapping), if they do.
    static func meet(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>) -> SIMD2<Double>? {
        let d1 = cross(b - a, c - a), d2 = cross(b - a, d - a), d3 = cross(d - c, a - c), d4 = cross(d - c, b - c)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return a + (b - a) * (d3 / (d3 - d4))
        }
        func on(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: SIMD2<Double>) -> Bool {
            cross(q - p, r - p) == 0 && min(p.x, q.x) <= r.x && r.x <= max(p.x, q.x) && min(p.y, q.y) <= r.y && r.y <= max(p.y, q.y)
        }
        if on(c, d, a) { return a }
        if on(c, d, b) { return b }
        if on(a, b, c) { return c }
        if on(a, b, d) { return d }
        return nil
    }

    @inline(__always) static func cross(_ u: SIMD2<Double>, _ v: SIMD2<Double>) -> Double { u.x * v.y - u.y * v.x }

    /// For each ring, the ring it lies inside, if any (the smallest such: a pupil's iris). Rings are
    /// bucketed by their bounds; one inside another has its first point inside it and its bounds
    /// within the other's. The engine keeps a pupil clear of its iris's outline; whether a tile
    /// touches the one it lies in is left to `Template.validate`.
    static func containers(_ rings: [[SIMD2<Double>]]) -> [Int?] {
        let bounds = rings.map { r -> (lo: SIMD2<Double>, hi: SIMD2<Double>) in
            (r.reduce(SIMD2(repeating: .infinity)) { pointwiseMin($0, $1) }, r.reduce(SIMD2(repeating: -.infinity)) { pointwiseMax($0, $1) })
        }
        let cell = 64.0
        var buckets: [SIMD2<Int>: [Int]] = [:]
        for (i, b) in bounds.enumerated() where rings[i].count >= 3 {
            for y in Int(b.lo.y / cell)...Int(b.hi.y / cell) {
                for x in Int(b.lo.x / cell)...Int(b.hi.x / cell) { buckets[SIMD2(x, y), default: []].append(i) }
            }
        }
        return rings.indices.map { i in
            guard rings[i].count >= 3 else { return nil }
            let b = bounds[i], p = rings[i][0]
            var best: Int?
            for j in buckets[SIMD2(Int(p.x / cell), Int(p.y / cell))] ?? [] where j != i {
                let o = bounds[j]
                guard o.lo.x <= b.lo.x, o.lo.y <= b.lo.y, o.hi.x >= b.hi.x, o.hi.y >= b.hi.y, contains(rings[j], p) else { continue }
                if let c = best, abs(area2(rings[c])) <= abs(area2(rings[j])) { continue }
                best = j
            }
            return best
        }
    }

    /// Where to number the grout: from its roomiest pixel down (the exact distance transform of the
    /// region map), each taken when it has `least` room to spare and is `spacing` from every one
    /// taken. The roomiest comes first, so it is the grout's primary label, whatever its room.
    static func groutSpots(_ map: RegionMap, grout: UInt32, spacing: Double, least: Double) -> [SIMD2<Double>] {
        let w = map.width, h = map.height
        let room = distanceTransform(w, h) { map.storage[$0] == grout }
        var best = 0
        for i in room.indices where room[i] > room[best] { best = i }
        guard room[best] > 0 else { return [] }
        let enough = Float((least + 1) * (least + 1))
        var order = room.indices.filter { room[$0] >= enough && $0 != best }
        order.sort { room[$0] != room[$1] ? room[$0] > room[$1] : $0 < $1 }
        // Taken spots by a grid of `spacing` cells: a candidate checks its own and the eight round it.
        var grid: [SIMD2<Int>: [SIMD2<Double>]] = [:]
        var taken: [SIMD2<Double>] = []
        let s2 = spacing * spacing
        for i in [best] + order {
            let p = SIMD2(Double(i % w) + 0.5, Double(i / w) + 0.5)
            let c = SIMD2(Int(p.x / spacing), Int(p.y / spacing))
            var near = false
            for dy in -1...1 {
                for dx in -1...1 {
                    for q in grid[c &+ SIMD2(dx, dy)] ?? [] where (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y) < s2 { near = true }
                }
            }
            if near { continue }
            taken.append(p)
            grid[c, default: []].append(p)
        }
        return taken
    }

    /// Squared Euclidean distance from each cell inside to the nearest cell outside (Felzenszwalb
    /// and Huttenlocher's separable transform); cells beyond the grid count as outside.
    static func distanceTransform(_ w: Int, _ h: Int, inside: (Int) -> Bool) -> [Float] {
        let big = Float(w * w + h * h)
        var d = [Float](repeating: 0, count: w * h)
        for i in d.indices where inside(i) { d[i] = big }
        let longest = max(w, h) + 2
        var f = [Float](repeating: 0, count: longest), out = f
        var v = [Int](repeating: 0, count: longest), z = [Float](repeating: 0, count: longest + 1)
        // One line of `count` cells (from `start`, every `step`), with outside at both ends.
        func pass(start: Int, step: Int, count: Int) {
            let m = count + 2
            f[0] = 0; f[m - 1] = 0
            for q in 0..<count { f[q + 1] = d[start + q * step] }
            var k = 0
            v[0] = 0; z[0] = -.infinity; z[1] = .infinity
            for q in 1..<m {
                let fq = f[q] + Float(q * q)
                var s = (fq - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
                while s <= z[k] {
                    k -= 1
                    s = (fq - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * (q - v[k]))
                }
                k += 1
                v[k] = q; z[k] = s; z[k + 1] = .infinity
            }
            k = 0
            for q in 0..<m {
                while z[k + 1] < Float(q) { k += 1 }
                out[q] = Float((q - v[k]) * (q - v[k])) + f[v[k]]
            }
            for q in 0..<count { d[start + q * step] = out[q + 1] }
        }
        for x in 0..<w { pass(start: x, step: w, count: h) }
        for y in 0..<h { pass(start: y * w, step: 1, count: w) }
        return d
    }

    /// Copied from Paint by Moonlight (`RegionFills.splitTJunctions` in PaintCore, internal there):
    /// Earcut drops ring vertices that became collinear with their neighbours; the neighbouring
    /// region still uses such a vertex, so it would be a T-junction, a source of pixel cracks on the
    /// GPU (and `Template.validate` fails it). Splits every triangle whose edge passes through an
    /// unused vertex. Exact: coordinates lie on the `Template.coordinateQuantum` grid.
    static func splitTJunctions(_ points: [SIMD2<Double>], _ tri: inout [UInt32]) {
        var used = [Bool](repeating: false, count: points.count)
        for i in tri { used[Int(i)] = true }
        guard used.contains(false) else { return }
        let scale = Double(1 / Template.coordinateQuantum)
        @inline(__always) func fixed(_ i: Int) -> SIMD2<Int64> {
            SIMD2(Int64((points[i].x * scale).rounded()), Int64((points[i].y * scale).rounded()))
        }
        var usedCoordinates = Set<SIMD2<Int64>>()
        for i in points.indices where used[i] { usedCoordinates.insert(fixed(i)) }
        for v in points.indices where !used[v] {
            let p = fixed(v)
            guard usedCoordinates.insert(p).inserted else { continue }
            var t = 0
            while t < tri.count {
                var split = false
                for k in 0..<3 {
                    let a = fixed(Int(tri[t + k])), b = fixed(Int(tri[t + (k + 1) % 3]))
                    let ab = b &- a, ap = p &- a, bp = p &- b
                    if ab.x * ap.y - ab.y * ap.x == 0 && (ab &* ap).wrappedSum() > 0 && (ab &* bp).wrappedSum() < 0 {
                        let ia = tri[t + k], ib = tri[t + (k + 1) % 3], ic = tri[t + (k + 2) % 3]
                        tri[t] = ia; tri[t + 1] = UInt32(v); tri[t + 2] = ic
                        tri.append(UInt32(v)); tri.append(ib); tri.append(ic)
                        split = true
                        break
                    }
                }
                if !split { t += 3 }
            }
        }
    }
}
