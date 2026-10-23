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

    /// A mosaic as a PaintCore template that `Template.validate` passes: region `i` is tile `i` in
    /// paint `tile.paint`, and the last region is the grout, every joint at once, in a paint of its own
    /// (the last palette entry, `mosaic.grout`), painted as one area (issue #6). Built directly, not
    /// re-traced: each tile's outline is its corners exactly (on `Template.coordinateQuantum`), a
    /// closed edge with the grout on its other side, and the grout is the canvas with every tile as
    /// a hole. A tile is numbered at its pole; one too small for the usual floor
    /// (`LabelSizing.minimumRadius`, a sliver cut in the gap fill) is a detail area, read zoomed in.
    /// The grout is numbered at its roomiest spots, spread over the canvas.
    public static func template(of mosaic: Mosaic, longSide: Int = templateLongSide) throws -> Template {
        let n = mosaic.tiles.count
        guard n > 0, mosaic.width > 0, mosaic.height > 0 else { throw TemplateError.noTiles }
        let k = Double(longSide) / Double(max(mosaic.width, mosaic.height))
        let width = max(Int((Double(mosaic.width) * k).rounded(.up)), 1)
        let height = max(Int((Double(mosaic.height) * k).rounded(.up)), 1)
        let quantum = Double(Template.coordinateQuantum)
        func snap(_ v: Double, _ limit: Int) -> Double { min(max((v / quantum).rounded() * quantum, 0), Double(limit)) }

        // Each tile's ring: snapped, without repeats, positive (clockwise on screen).
        var outlines: [[SIMD2<Double>]] = []
        outlines.reserveCapacity(n)
        for (i, tile) in mosaic.tiles.enumerated() {
            var ring: [SIMD2<Double>] = []
            for c in tile.corners {
                let p = SIMD2(snap(Double(c.x) * k, width), snap(Double(c.y) * k, height))
                if ring.last != p { ring.append(p) }
            }
            while ring.count > 1 && ring.first == ring.last { ring.removeLast() }
            let a = area2(ring)
            guard ring.count >= 3, a != 0 else { throw TemplateError.degenerateTile(i) }
            if a < 0 { ring.reverse() }
            outlines.append(ring)
        }
        let border: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(Double(width), 0), SIMD2(Double(width), Double(height)), SIMD2(0, Double(height))]

        // Palette: the mosaic's paints, then the grout's.
        let palette = (mosaic.palette + [mosaic.grout]).map { rgb in
            PaletteColor(oklab: ColorScience.encodedToOKLab(rgb, space: .sRGB), rgb: rgb)
        }
        let groutRegion = UInt32(n), groutPaint = UInt32(mosaic.palette.count)

        // Edges: one closed edge per tile (tile on its left, grout on its right), then the border.
        var points: [SIMD2<Float>] = [], edges: [BoundaryEdge] = []
        for (i, ring) in (outlines + [border]).enumerated() {
            edges.append(BoundaryEdge(left: UInt32(i), right: i == n ? BoundaryEdge.outside : groutRegion,
                                      pointStart: UInt32(points.count), pointCount: UInt32(ring.count + 1)))
            points += (ring + [ring[0]]).map { SIMD2<Float>($0) }
        }
        var ringEdges: [EdgeRef] = [], rings: [Ring] = []
        for i in 0..<n {
            rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: 1, isHole: false))
            ringEdges.append(EdgeRef(edge: UInt32(i), reversed: false))
        }
        rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: 1, isHole: false))
        ringEdges.append(EdgeRef(edge: UInt32(n), reversed: false))
        for i in 0..<n {
            rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: 1, isHole: true))
            ringEdges.append(EdgeRef(edge: UInt32(i), reversed: true))
        }

        // The grout as one polygon: the border, then each tile reversed (a hole).
        var grout = FlatPolygon()
        grout.points = border
        grout.closeRing()
        for ring in outlines {
            grout.points += ring.reversed()
            grout.closeRing()
        }

        // Fills.
        var mesh = FillMesh()
        var earcut = Earcut()
        var spans: [(start: UInt32, count: UInt32)] = []
        func fill(_ poly: [SIMD2<Double>], holeStarts: [Int], region: UInt32) {
            var tri: [UInt32] = []
            earcut.triangulate(poly, holeStarts: holeStarts, into: &tri)
            splitTJunctions(poly, &tri)
            let base = UInt32(mesh.vertices.count)
            mesh.vertices += poly.map { SIMD2<Float>($0) }
            mesh.vertexRegion += [UInt32](repeating: region, count: poly.count)
            spans.append((UInt32(mesh.indices.count), UInt32(tri.count)))
            mesh.indices += tri.map { $0 + base }
        }
        for (i, ring) in outlines.enumerated() { fill(ring, holeStarts: [], region: UInt32(i)) }
        fill(grout.points, holeStarts: Array(grout.ringStarts[1..<grout.ringCount]), region: groutRegion)

        // The region map, for hit testing: each tile's pixels by their centres, the rest grout.
        var map = RegionMap(width: width, height: height, repeating: groutRegion)
        for (i, ring) in outlines.enumerated() {
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
        var labels: [Label] = []
        var regions: [Region] = []
        var detail: [UInt32] = []
        func floor(_ paint: UInt32) -> Double {
            Double(LabelSizing.minimumRadius(digits: LabelSizing.digitCount(colorIndex: paint)))
        }
        for (i, ring) in outlines.enumerated() {
            var poly = FlatPolygon()
            poly.points = ring
            poly.closeRing()
            let centre = ring.reduce(SIMD2<Double>.zero, +) / Double(ring.count)
            let pole = PolyLabel.find(poly, precision: 0.005, seed: centre)
            let paint = UInt32(mosaic.tiles[i].paint)
            if pole.distance < floor(paint) { detail.append(UInt32(i)) }
            regions.append(region(paint: paint, area2: area2(ring), outer: ring, radius: pole.distance, width: width, height: height,
                                  rings: (UInt32(i), 1), labels: (UInt32(labels.count), 1), fill: spans[i]))
            labels.append(Label(position: SIMD2<Float>(pole.position), radius: shave(pole.distance), region: UInt32(i)))
        }
        let spots = groutSpots(map, grout: groutRegion, spacing: Double(max(width, height)) / 16, least: floor(groutPaint))
        var groutLabels: [Label] = []
        var groutRadius = 0.0
        for seed in spots {
            let pole = PolyLabel.find(grout, precision: 0.01, seed: seed)
            guard pole.distance > 0 else { continue }
            if groutLabels.isEmpty { groutRadius = pole.distance }
            groutLabels.append(Label(position: SIMD2<Float>(pole.position), radius: shave(pole.distance), region: groutRegion))
        }
        if groutRadius < floor(groutPaint) { detail.append(groutRegion) }
        let groutArea2 = (0..<grout.ringCount).reduce(0.0) { $0 + grout.area2(ring: $1) }
        regions.append(region(paint: groutPaint, area2: groutArea2, outer: border, radius: groutRadius, width: width, height: height,
                              rings: (UInt32(n), UInt32(n + 1)), labels: (UInt32(labels.count), UInt32(groutLabels.count)), fill: spans[n]))
        labels += groutLabels

        var template = Template(width: width, height: height, colorSpace: .sRGB, palette: palette, regions: regions,
                                points: points, edges: edges, ringEdges: ringEdges, rings: rings, labels: labels,
                                mesh: mesh, regionMap: map)
        template.detailRegions = detail
        return template
    }

    private static func region(paint: UInt32, area2: Double, outer: [SIMD2<Double>], radius: Double, width: Int, height: Int,
                               rings: (UInt32, UInt32), labels: (UInt32, UInt32), fill: (start: UInt32, count: UInt32)) -> Region {
        let xs = outer.map(\.x), ys = outer.map(\.y)
        let bounds = PixelBounds(minX: Int32(max(0, xs.min()!.rounded(.down))), minY: Int32(max(0, ys.min()!.rounded(.down))),
                                 maxX: Int32(min(Double(width), xs.max()!.rounded(.up))),
                                 maxY: Int32(min(Double(height), ys.max()!.rounded(.up))))
        return Region(colorIndex: paint, area: Float(area2 / 2), bounds: bounds, inscribedRadius: Float(radius),
                      ringStart: rings.0, ringCount: rings.1, labelStart: labels.0, labelCount: labels.1,
                      indexStart: fill.start, indexCount: fill.count)
    }

    /// A label's free radius as stored: never more than measured, whatever Float makes of it.
    private static func shave(_ d: Double) -> Float { Float(d).nextDown }

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

    /// Where to number the grout: its pixels from the roomiest down (the exact distance transform
    /// of the region map), each taken when it has `least` room and is `spacing` from every one taken.
    /// The roomiest comes first, so it is the grout's primary label, whatever its room.
    static func groutSpots(_ map: RegionMap, grout: UInt32, spacing: Double, least: Double) -> [SIMD2<Double>] {
        let w = map.width, h = map.height
        let room = distanceTransform(w, h) { map.storage[$0] == grout }
        var order = (0..<(w * h)).filter { room[$0] > 0 }
        order.sort { room[$0] != room[$1] ? room[$0] > room[$1] : $0 < $1 }
        var taken: [SIMD2<Double>] = []
        let s2 = spacing * spacing
        for i in order {
            let r = Double(room[i]).squareRoot()
            if !taken.isEmpty && r < least + 1 { break }
            let p = SIMD2(Double(i % w) + 0.5, Double(i / w) + 0.5)
            if taken.contains(where: { let d = $0 - p; return (d * d).sum() < s2 }) { continue }
            taken.append(p)
        }
        return taken
    }

    /// Squared Euclidean distance from each cell inside to the nearest cell outside (Felzenszwalb
    /// and Huttenlocher's separable transform); cells beyond the grid count as outside.
    static func distanceTransform(_ w: Int, _ h: Int, inside: (Int) -> Bool) -> [Float] {
        let big = Float(w * w + h * h)
        var d = (0..<(w * h)).map { inside($0) ? big : 0 }
        func pass(_ f: [Float]) -> [Float] {
            // 1-D lower envelope of parabolas, with the grid's ends as outside.
            let m = f.count + 2
            let g = [0] + f + [0]
            var out = [Float](repeating: 0, count: m)
            var v = [Int](repeating: 0, count: m), z = [Float](repeating: 0, count: m + 1)
            var k = 0
            z[0] = -.infinity; z[1] = .infinity
            for q in 1..<m {
                var s: Float
                repeat {
                    let p = v[k]
                    s = ((g[q] + Float(q * q)) - (g[p] + Float(p * p))) / Float(2 * (q - p))
                    if s <= z[k] { k -= 1 } else { break }
                } while k >= 0
                k += 1
                v[k] = q; z[k] = s; z[k + 1] = .infinity
            }
            k = 0
            for q in 0..<m {
                while z[k + 1] < Float(q) { k += 1 }
                let p = v[k]
                out[q] = Float((q - p) * (q - p)) + g[p]
            }
            return Array(out[1..<(m - 1)])
        }
        for x in 0..<w {
            let col = pass((0..<h).map { d[$0 * w + x] })
            for y in 0..<h { d[y * w + x] = col[y] }
        }
        for y in 0..<h {
            let row = pass(Array(d[(y * w)..<(y * w + w)]))
            d.replaceSubrange((y * w)..<(y * w + w), with: row)
        }
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
