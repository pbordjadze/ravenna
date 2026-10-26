#if DEBUG
import Foundation
import PaintCore

/// A deterministic template with real vector geometry — a mosaic of curvy cells, some
/// holding a blob (so the cell has a hole) and some blobs holding a disc — built the same
/// way the production vectorizer lays out its output: shared boundary polylines, rings of
/// edge references, a watertight per-region triangulation, labels and a region map.
///
/// Used by canvas tests and demo scenarios (Debug builds only); it does not depend on the photo
/// pipeline.
nonisolated enum SyntheticTemplate {
    nonisolated struct Options: Sendable {
        var width = 1200
        var height = 1600
        var columns = 12
        var rows = 16
        /// Probability that a cell holds a blob.
        var blobChance: Float = 0.45
        /// Probability that a blob holds a disc.
        var discChance: Float = 0.4
        var seed: UInt64 = 7
    }

    static func make(_ options: Options = Options()) -> Template {
        var builder = Builder(options: options)
        return builder.build()
    }

    /// A harmonious "abstract landscape" palette in Display P3: sky, sunset, land, accents.
    static let palette: [PaletteColor] = {
        let lch: [(Float, Float, Float)] = [
            (0.34, 0.09, 262),  // 1 deep navy
            (0.52, 0.13, 248),  // 2 ocean
            (0.79, 0.08, 232),  // 3 sky
            (0.88, 0.05, 20),   // 4 blush
            (0.88, 0.07, 88),   // 5 sand
            (0.82, 0.15, 84),   // 6 mustard
            (0.77, 0.13, 58),   // 7 apricot
            (0.68, 0.17, 32),   // 8 coral
            (0.50, 0.15, 30),   // 9 brick
            (0.63, 0.10, 190),  // 10 teal
            (0.74, 0.09, 142),  // 11 sage
            (0.45, 0.10, 150),  // 12 forest
            (0.44, 0.13, 330),  // 13 plum
            (0.96, 0.02, 95),   // 14 cream
        ]
        return lch.map { l, c, h in
            let rad = h * .pi / 180
            return PaletteColor(oklab: SIMD3(l, c * cos(rad), c * sin(rad)), space: .displayP3)
        }
    }()

    /// Palette indices per horizontal band (top to bottom), and accents for blobs.
    fileprivate static let bands: [[UInt32]] = [[0, 1, 2], [2, 3, 4, 12], [5, 6, 7, 8], [9, 10, 11, 4]]
    fileprivate static let accents: [UInt32] = [13, 7, 5, 12, 3, 9, 2]
}

nonisolated private struct Builder {
    let o: SyntheticTemplate.Options
    var rng: SplitMix64

    var points: [SIMD2<Float>] = []
    var edges: [BoundaryEdge] = []
    /// Per region: rings as (edge refs, isHole), outer first.
    var regionRings: [[([EdgeRef], Bool)]] = []
    var regionColor: [UInt32] = []
    /// Per region: the star centre its triangulation fans/zips around.
    var regionCenter: [SIMD2<Float>] = []

    init(options: SyntheticTemplate.Options) {
        o = options
        rng = SplitMix64(seed: options.seed)
    }

    mutating func random() -> Float { rng.nextFloat() }

    mutating func build() -> Template {
        let cols = o.columns, rows = o.rows
        let W = Float(o.width), H = Float(o.height)
        let cw = W / Float(cols), ch = H / Float(rows)
        let cellCount = cols * rows

        // Jittered lattice; border vertices only slide along the border.
        var lattice = [SIMD2<Float>](repeating: .zero, count: (cols + 1) * (rows + 1))
        func li(_ i: Int, _ j: Int) -> Int { j * (cols + 1) + i }
        for j in 0...rows {
            for i in 0...cols {
                var p = SIMD2(Float(i) * cw, Float(j) * ch)
                let jx = (random() - 0.5) * 0.5 * cw, jy = (random() - 0.5) * 0.5 * ch
                if i > 0 && i < cols { p.x += jx }
                if j > 0 && j < rows { p.y += jy }
                lattice[li(i, j)] = p
            }
        }

        // Decide blobs and discs up front so every region index is known before edges exist.
        var blobOf = [Int?](repeating: nil, count: cellCount)
        var discOf: [Int: Int] = [:]
        var next = cellCount
        for c in 0..<cellCount where random() < o.blobChance {
            blobOf[c] = next
            next += 1
        }
        for c in 0..<cellCount {
            if let b = blobOf[c], random() < o.discChance {
                discOf[b] = next
                next += 1
            }
        }
        let regionCount = next
        regionRings = Array(repeating: [], count: regionCount)
        regionColor = Array(repeating: 0, count: regionCount)
        regionCenter = Array(repeating: .zero, count: regionCount)

        assignColors(cols: cols, rows: rows, blobOf: blobOf, discOf: discOf)

        let outside = BoundaryEdge.outside
        func cell(_ i: Int, _ j: Int) -> UInt32 { UInt32(j * cols + i) }

        // Horizontal edges h[i][j] (j = 0...rows) and vertical edges v[i][j] (i = 0...cols).
        // Stored so that `left` is always a real region (the border edges are flipped).
        var hEdge = [UInt32](repeating: 0, count: cols * (rows + 1))
        var vEdge = [UInt32](repeating: 0, count: (cols + 1) * rows)
        for j in 0...rows {
            for i in 0..<cols {
                let a = lattice[li(i, j)], b = lattice[li(i + 1, j)]
                if j == rows {
                    hEdge[j * cols + i] = addEdge(from: b, to: a, left: cell(i, j - 1), right: outside, wavy: false)
                } else {
                    hEdge[j * cols + i] = addEdge(
                        from: a, to: b, left: cell(i, j), right: j > 0 ? cell(i, j - 1) : outside, wavy: j > 0)
                }
            }
        }
        for j in 0..<rows {
            for i in 0...cols {
                let a = lattice[li(i, j)], b = lattice[li(i, j + 1)]
                if i == 0 {
                    vEdge[j * (cols + 1) + i] = addEdge(from: b, to: a, left: cell(0, j), right: outside, wavy: false)
                } else {
                    vEdge[j * (cols + 1) + i] = addEdge(
                        from: a, to: b, left: cell(i - 1, j), right: i < cols ? cell(i, j) : outside, wavy: i < cols)
                }
            }
        }

        // Cell rings: top → right → bottom → left (clockwise on screen).
        for j in 0..<rows {
            for i in 0..<cols {
                let c = j * cols + i
                let ring = [
                    EdgeRef(edge: hEdge[j * cols + i], reversed: false),
                    EdgeRef(edge: vEdge[j * (cols + 1) + i + 1], reversed: false),
                    EdgeRef(edge: hEdge[(j + 1) * cols + i], reversed: j + 1 != rows),
                    EdgeRef(edge: vEdge[j * (cols + 1) + i], reversed: i != 0),
                ]
                regionRings[c].append((ring, false))
                let corners = [lattice[li(i, j)], lattice[li(i + 1, j)], lattice[li(i + 1, j + 1)], lattice[li(i, j + 1)]]
                regionCenter[c] = (corners[0] + corners[1] + corners[2] + corners[3]) / 4
            }
        }

        // Blobs (polar curves around the cell centre) and discs inside them.
        for c in 0..<cellCount {
            guard let blob = blobOf[c] else { continue }
            let center = regionCenter[c]
            let clearance = distanceToRing(center, polygon(regionRings[c][0].0))
            let base = 0.62 * clearance / 1.25
            let p1 = random() * 2 * .pi, p2 = random() * 2 * .pi
            let blobEdge = addLoop(center: center, left: UInt32(blob), right: UInt32(c)) { t in
                base * (1 + 0.16 * sin(3 * t + p1) + 0.07 * sin(5 * t + p2))
            }
            regionRings[blob].append(([EdgeRef(edge: blobEdge, reversed: false)], false))
            regionRings[c].append(([EdgeRef(edge: blobEdge, reversed: true)], true))
            regionCenter[blob] = center
            if let disc = discOf[blob] {
                let r = base * 0.77 * 0.45
                let discEdge = addLoop(center: center, left: UInt32(disc), right: UInt32(blob)) { _ in r }
                regionRings[disc].append(([EdgeRef(edge: discEdge, reversed: false)], false))
                regionRings[blob].append(([EdgeRef(edge: discEdge, reversed: true)], true))
                regionCenter[disc] = center
            }
        }

        // Triangulate each region: a fan around its star centre, or a zip between the outer
        // ring and its (single, concentric) hole.
        var vertices: [SIMD2<Float>] = []
        var vertexRegion: [UInt32] = []
        var indices: [UInt32] = []
        var indexSpans: [(UInt32, UInt32)] = []
        for r in 0..<regionCount {
            let start = UInt32(indices.count)
            let outer = polygon(regionRings[r][0].0)
            let base = UInt32(vertices.count)
            if regionRings[r].count > 1 {
                // The hole's own (forward) loop runs in the same angular direction as `outer`.
                let holeEdge = regionRings[r][1].0[0].edge
                let hole = Array(pointsOf(edges[Int(holeEdge)]).dropLast())
                vertices.append(contentsOf: outer)
                vertices.append(contentsOf: hole)
                for t in zip(outer: outer, inner: hole, center: regionCenter[r]) {
                    indices.append(base + t.0); indices.append(base + t.1); indices.append(base + t.2)
                }
            } else {
                vertices.append(regionCenter[r])
                vertices.append(contentsOf: outer)
                let n = UInt32(outer.count)
                for k in 0..<n {
                    indices.append(base); indices.append(base + 1 + k); indices.append(base + 1 + (k + 1) % n)
                }
            }
            vertexRegion.append(contentsOf: repeatElement(UInt32(r), count: vertices.count - Int(base)))
            indexSpans.append((start, UInt32(indices.count) - start))
        }

        // Region map: paint outer rings in region order (cells, blobs, discs) so inner shapes
        // overwrite their hosts exactly where the holes are.
        var map = [UInt32](repeating: .max, count: o.width * o.height)
        for r in 0..<regionCount {
            fill(polygon(regionRings[r][0].0), value: UInt32(r), into: &map)
        }
        // Pixels exactly on the canvas border can miss every half-open span; inherit a neighbour.
        for i in map.indices where map[i] == .max {
            map[i] = i % o.width > 0 ? map[i - 1] : (i >= o.width ? map[i - o.width] : 0)
        }
        let regionMap = RegionMap(width: o.width, height: o.height, storage: map)

        // Labels at the pole of inaccessibility (largest inscribed disc) of each region.
        let dist = DistanceTransform.interiorDistance(labels: regionMap)
        var bounds = [PixelBounds](repeating: .empty, count: regionCount)
        var best = [Float](repeating: -1, count: regionCount)
        var bestPos = [SIMD2<Float>](repeating: .zero, count: regionCount)
        map.withUnsafeBufferPointer { m in
            dist.storage.withUnsafeBufferPointer { d in
                for y in 0..<o.height {
                    for x in 0..<o.width {
                        let i = y * o.width + x
                        let r = Int(m[i])
                        bounds[r].include(x: x, y: y)
                        if d[i] > best[r] {
                            best[r] = d[i]
                            bestPos[r] = SIMD2(Float(x) + 0.5, Float(y) + 0.5)
                        }
                    }
                }
            }
        }

        var rings: [Ring] = []
        var ringEdges: [EdgeRef] = []
        var regions: [Region] = []
        var labels: [Label] = []
        for r in 0..<regionCount {
            let ringStart = UInt32(rings.count)
            for (refs, isHole) in regionRings[r] {
                rings.append(Ring(edgeStart: UInt32(ringEdges.count), edgeCount: UInt32(refs.count), isHole: isHole))
                ringEdges.append(contentsOf: refs)
            }
            let hasLabel = best[r] > 0
            // Exact polygon area (outer ring minus holes), like the production vectorizer.
            let polygonArea = regionRings[r].reduce(Float(0)) { sum, ring in
                let a = shoelace(polygon(ring.0))
                return ring.1 ? sum - abs(a) : sum + abs(a)
            }
            regions.append(Region(
                colorIndex: regionColor[r], area: polygonArea, bounds: bounds[r], inscribedRadius: max(0, best[r]),
                ringStart: ringStart, ringCount: UInt32(regionRings[r].count),
                labelStart: UInt32(labels.count), labelCount: hasLabel ? 1 : 0,
                indexStart: indexSpans[r].0, indexCount: indexSpans[r].1))
            if hasLabel { labels.append(Label(position: bestPos[r], radius: best[r], region: UInt32(r))) }
        }

        return Template(
            width: o.width, height: o.height, colorSpace: .displayP3,
            palette: SyntheticTemplate.palette, regions: regions,
            points: points, edges: edges, ringEdges: ringEdges, rings: rings,
            labels: labels,
            mesh: FillMesh(vertices: vertices, vertexRegion: vertexRegion, indices: indices),
            regionMap: regionMap)
    }

    // MARK: Colors

    private mutating func assignColors(cols: Int, rows: Int, blobOf: [Int?], discOf: [Int: Int]) {
        let bands = SyntheticTemplate.bands
        for j in 0..<rows {
            for i in 0..<cols {
                let c = j * cols + i
                let x = (Float(i) + 0.5) / Float(cols), y = (Float(j) + 0.5) / Float(rows)
                // Wavy horizon lines so the bands read like a landscape.
                let v = y + 0.07 * sin(x * 2 * .pi * 1.3 + 1) + (random() - 0.5) * 0.12
                let band = bands[min(bands.count - 1, max(0, Int(v * Float(bands.count))))]
                var avoid: Set<UInt32> = []
                if i > 0 { avoid.insert(regionColor[c - 1]) }
                if j > 0 { avoid.insert(regionColor[c - cols]) }
                let choices = band.filter { !avoid.contains($0) }
                let pool = choices.isEmpty ? band : choices
                regionColor[c] = pool[Int(random() * Float(pool.count)) % pool.count]
            }
        }
        let accents = SyntheticTemplate.accents
        for c in blobOf.indices {
            guard let b = blobOf[c] else { continue }
            let pool = accents.filter { $0 != regionColor[c] }
            regionColor[b] = pool[Int(random() * Float(pool.count)) % pool.count]
            if let d = discOf[b] {
                let inner = accents.filter { $0 != regionColor[b] }
                regionColor[d] = inner[Int(random() * Float(inner.count)) % inner.count]
            }
        }
        // Every palette color must appear at least once.
        let used = Set(regionColor)
        var spare = Array(regionColor.count > blobOf.count ? blobOf.count..<regionColor.count : 0..<0)
        for color in 0..<UInt32(SyntheticTemplate.palette.count) where !used.contains(color) {
            if let r = spare.popLast() { regionColor[r] = color }
        }
    }

    // MARK: Geometry

    private mutating func addEdge(
        from a: SIMD2<Float>, to b: SIMD2<Float>, left: UInt32, right: UInt32, wavy: Bool
    ) -> UInt32 {
        let d = b - a
        let len = (d * d).sum().squareRoot()
        let n = max(3, Int((len / 12).rounded()))
        let normal = SIMD2(-d.y, d.x) / len
        let amp = wavy ? len * 0.06 * (random() * 2 - 1) : 0
        let phase = random() * 2 * .pi
        let start = points.count
        for k in 0...n {
            let s = Float(k) / Float(n)
            if k == 0 {
                points.append(a)
            } else if k == n {
                points.append(b)
            } else {
                let bump = amp * sin(.pi * s) * (0.65 + 0.35 * sin(2 * .pi * s + phase))
                points.append(a + d * s + normal * bump)
            }
        }
        edges.append(BoundaryEdge(left: left, right: right, pointStart: UInt32(start), pointCount: UInt32(n + 1)))
        return UInt32(edges.count - 1)
    }

    /// A closed loop `center + r(θ)·(cos θ, sin θ)`, θ increasing (clockwise on screen), so
    /// the enclosed region is on its left.
    private mutating func addLoop(
        center: SIMD2<Float>, left: UInt32, right: UInt32, radius: (Float) -> Float
    ) -> UInt32 {
        let n = max(20, Int((2 * .pi * radius(0) / 9).rounded()))
        let start = points.count
        for k in 0..<n {
            let t = Float(k) / Float(n) * 2 * .pi
            points.append(center + radius(t) * SIMD2(cos(t), sin(t)))
        }
        points.append(points[start])
        edges.append(BoundaryEdge(left: left, right: right, pointStart: UInt32(start), pointCount: UInt32(n + 1)))
        return UInt32(edges.count - 1)
    }

    private func pointsOf(_ e: BoundaryEdge) -> ArraySlice<SIMD2<Float>> {
        points[Int(e.pointStart)..<Int(e.pointStart + e.pointCount)]
    }

    /// The closed polygon of a ring (first point not repeated), like `Template.polygon(of:)`.
    private func polygon(_ refs: [EdgeRef]) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for ref in refs {
            let pts = pointsOf(edges[Int(ref.edge)])
            if ref.reversed { out.append(contentsOf: pts.reversed().dropLast()) } else { out.append(contentsOf: pts.dropLast()) }
        }
        return out
    }

    private func shoelace(_ poly: [SIMD2<Float>]) -> Float {
        var sum: Double = 0
        for k in poly.indices {
            let a = poly[k], b = poly[(k + 1) % poly.count]
            sum += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        return Float(sum / 2)
    }

    private func distanceToRing(_ p: SIMD2<Float>, _ ring: [SIMD2<Float>]) -> Float {
        var best = Float.infinity
        for k in ring.indices {
            let a = ring[k], b = ring[(k + 1) % ring.count]
            let ab = b - a, ap = p - a
            let t = min(1, max(0, (ap * ab).sum() / max((ab * ab).sum(), 1e-9)))
            let q = a + ab * t - p
            best = min(best, (q * q).sum().squareRoot())
        }
        return best
    }

    /// Triangulates the annulus between two rings that are both angularly monotone
    /// (increasing) around `center`. Indices: outer `0..<m`, inner `m..<m+n`.
    private func zip(outer: [SIMD2<Float>], inner: [SIMD2<Float>], center: SIMD2<Float>) -> [(UInt32, UInt32, UInt32)] {
        let m = outer.count, n = inner.count
        func angle(_ p: SIMD2<Float>) -> Float { atan2(p.y - center.y, p.x - center.x) }
        let base = angle(outer[0])
        func rel(_ p: SIMD2<Float>) -> Float {
            var a = angle(p) - base
            while a < 0 { a += 2 * .pi }
            while a >= 2 * .pi { a -= 2 * .pi }
            return a
        }
        // Start the inner ring at its first vertex at or after the outer start angle.
        var innerStart = 0
        var smallest = Float.infinity
        for k in 0..<n where rel(inner[k]) < smallest {
            smallest = rel(inner[k])
            innerStart = k
        }
        func outerAngle(_ i: Int) -> Float { i == m ? 2 * .pi : (i == 0 ? 0 : rel(outer[i])) }
        func innerIndex(_ j: Int) -> Int { (innerStart + j) % n }
        func innerAngle(_ j: Int) -> Float { rel(inner[innerIndex(j)]) + (j == n ? 2 * .pi : 0) }
        func signedArea(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
        }
        var tris: [(UInt32, UInt32, UInt32)] = []
        var i = 0, j = 0
        while i < m || j < n {
            var advanceOuter = j >= n || (i < m && outerAngle(i + 1) <= innerAngle(j + 1))
            if i < m && j < n {
                // Sparse rings can make the angular choice fold a triangle over; take the
                // other step when only it keeps the orientation.
                let o0 = outer[i % m], o1 = outer[(i + 1) % m]
                let i0 = inner[innerIndex(j)], i1 = inner[innerIndex(j + 1)]
                let outerOK = signedArea(o0, o1, i0) > 0, innerOK = signedArea(o0, i1, i0) > 0
                if advanceOuter && !outerOK && innerOK { advanceOuter = false }
                if !advanceOuter && !innerOK && outerOK { advanceOuter = true }
            }
            let oi = UInt32(i % m), ij = UInt32(m + innerIndex(j))
            if advanceOuter {
                tris.append((oi, UInt32((i + 1) % m), ij))
                i += 1
            } else {
                tris.append((oi, UInt32(m + innerIndex(j + 1)), ij))
                j += 1
            }
        }
        return tris
    }

    /// Scanline-fills a polygon (pixel centres, half-open spans) with `value`.
    private func fill(_ poly: [SIMD2<Float>], value: UInt32, into map: inout [UInt32]) {
        let w = o.width, h = o.height
        var minY = Float.infinity, maxY = -Float.infinity
        for p in poly { minY = min(minY, p.y); maxY = max(maxY, p.y) }
        let y0 = max(0, Int((minY - 0.5).rounded(.up))), y1 = min(h - 1, Int((maxY - 0.5).rounded(.down)))
        guard y0 <= y1 else { return }
        var xs: [Float] = []
        let n = poly.count
        for y in y0...y1 {
            let sy = Float(y) + 0.5
            xs.removeAll(keepingCapacity: true)
            for k in 0..<n {
                let a = poly[k], b = poly[(k + 1) % n]
                if (a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy) {
                    xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let xa = max(0, Int((xs[k] - 0.5).rounded(.up)))
                let xb = min(w, Int((xs[k + 1] - 0.5).rounded(.up)))
                if xa < xb { for x in xa..<xb { map[y * w + x] = value } }
                k += 2
            }
        }
    }
}

// MARK: - Edge map stand-in

nonisolated extension SyntheticTemplate {
    /// A stand-in for the app's learned edge detector in demo scenarios and tests: the photo's
    /// OKLab gradient magnitude after a light blur (sigma 1.2 px), normalized at its 99th
    /// percentile with a gentle lift (power 0.8). It finds the outlines HED finds, and more
    /// texture; pass a photo of about 640 px (the generator resamples any size).
    static func edgeMap(for image: RGBAImage) -> EdgeMap {
        let w = image.width, h = image.height
        let lab = ColorScience.okLabImage(from: image).storage
        let radius = 4
        let kernel: [Float] = {
            let k = (-radius...radius).map { exp(-Float($0 * $0) / (2 * 1.2 * 1.2)) }
            let sum = k.reduce(0, +)
            return k.map { $0 / sum }
        }()
        var magnitude = [Float](repeating: 0, count: w * h)
        for channel in 0..<3 {
            var row = [Float](repeating: 0, count: w * h), blurred = row
            for y in 0..<h {
                for x in 0..<w {
                    var v: Float = 0
                    for (k, weight) in kernel.enumerated() { v += weight * lab[y * w + min(max(x + k - radius, 0), w - 1)][channel] }
                    row[y * w + x] = v
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    var v: Float = 0
                    for (k, weight) in kernel.enumerated() { v += weight * row[min(max(y + k - radius, 0), h - 1) * w + x] }
                    blurred[y * w + x] = v
                }
            }
            for y in 1..<max(h - 1, 1) {
                for x in 1..<max(w - 1, 1) {
                    let gx = blurred[y * w + x + 1] - blurred[y * w + x - 1]
                    let gy = blurred[(y + 1) * w + x] - blurred[(y - 1) * w + x]
                    magnitude[y * w + x] += gx * gx + gy * gy
                }
            }
        }
        magnitude = magnitude.map { $0.squareRoot() }
        let reference = max(magnitude.sorted()[min(magnitude.count - 1, magnitude.count * 99 / 100)], 1e-6)
        return EdgeMap(width: w, height: h, values: magnitude.map { UInt8((pow(min($0 / reference, 1), 0.8) * 255).rounded()) })
    }
}
#endif
