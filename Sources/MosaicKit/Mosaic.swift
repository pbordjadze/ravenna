/// A mosaic to set: its tiles, each a small polygon with the number of its paint (a smalti), on a
/// canvas measured in the units its picture was laid out in. Read from the bundle's JSON, which the
/// bench (`sketchbook/bundle.py`) writes from the prototype's design.
///
/// Shared by the app and the Linux tests: plain Swift, no frameworks.
nonisolated public struct Mosaic: Sendable, Equatable {
    nonisolated public struct Tile: Sendable, Equatable {
        /// Corners in canvas units, in order round the tile.
        public var corners: [SIMD2<Float>]
        /// Index into `Mosaic.palette`. The painter sees `paint + 1`.
        public var paint: Int
        /// Matte stone rather than glass: the tiles of a face, as Byzantine faces were set.
        public var stone: Bool

        public init(corners: [SIMD2<Float>], paint: Int, stone: Bool = false) {
            self.corners = corners; self.paint = paint; self.stone = stone
        }

        /// The mean of the corners: where a tile's number sits and where it grows from when set.
        public var centre: SIMD2<Float> {
            corners.reduce(SIMD2<Float>(0, 0), +) / Float(max(corners.count, 1))
        }

        public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
            var lo = SIMD2<Float>(.infinity, .infinity), hi = -lo
            for c in corners { lo = pointwiseMin(lo, c); hi = pointwiseMax(hi, c) }
            return (lo, hi)
        }

        /// Even-odd point in polygon.
        public func contains(_ p: SIMD2<Float>) -> Bool {
            var inside = false
            var j = corners.count - 1
            for i in corners.indices {
                let a = corners[i], b = corners[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }

    /// Canvas size in units.
    public var width: Float
    public var height: Float
    /// The joint's colour when the grout is light: sRGB, 0...1.
    public var grout: SIMD3<Float>
    /// The smalti: sRGB, 0...1.
    public var palette: [SIMD3<Float>]
    public var tiles: [Tile]

    public init(width: Float, height: Float, grout: SIMD3<Float>, palette: [SIMD3<Float>], tiles: [Tile]) {
        self.width = width; self.height = height; self.grout = grout; self.palette = palette; self.tiles = tiles
    }

    /// How many tiles each paint has.
    public var tilesPerPaint: [Int] {
        var n = [Int](repeating: 0, count: palette.count)
        for t in tiles where n.indices.contains(t.paint) { n[t.paint] += 1 }
        return n
    }
}

nonisolated extension Mosaic: Codable {
    private enum Keys: String, CodingKey { case size, grout, palette, tiles }
    private enum TileKeys: String, CodingKey { case c, p, s }

    public enum FormatError: Error, Equatable {
        case badSize, badColor, badTile(Int)
    }

    public init(from decoder: any Decoder) throws {
        let k = try decoder.container(keyedBy: Keys.self)
        let size = try k.decode([Float].self, forKey: .size)
        guard size.count == 2, size[0] > 0, size[1] > 0 else { throw FormatError.badSize }
        func color(_ v: [Float]) throws -> SIMD3<Float> {
            guard v.count == 3 else { throw FormatError.badColor }
            return SIMD3(v[0], v[1], v[2])
        }
        let palette = try k.decode([[Float]].self, forKey: .palette).map(color)
        var list = try k.nestedUnkeyedContainer(forKey: .tiles)
        var tiles: [Tile] = []
        while !list.isAtEnd {
            let t = try list.nestedContainer(keyedBy: TileKeys.self)
            let flat = try t.decode([Float].self, forKey: .c)
            let paint = try t.decode(Int.self, forKey: .p)
            guard flat.count >= 6, flat.count % 2 == 0, palette.indices.contains(paint) else {
                throw FormatError.badTile(tiles.count)
            }
            let corners = stride(from: 0, to: flat.count, by: 2).map { SIMD2(flat[$0], flat[$0 + 1]) }
            tiles.append(Tile(corners: corners, paint: paint, stone: (try t.decodeIfPresent(Int.self, forKey: .s) ?? 0) != 0))
        }
        self.init(width: size[0], height: size[1], grout: try color(try k.decode([Float].self, forKey: .grout)),
                  palette: palette, tiles: tiles)
    }

    public func encode(to encoder: any Encoder) throws {
        var k = encoder.container(keyedBy: Keys.self)
        try k.encode([width, height], forKey: .size)
        try k.encode([grout.x, grout.y, grout.z], forKey: .grout)
        try k.encode(palette.map { [$0.x, $0.y, $0.z] }, forKey: .palette)
        var list = k.nestedUnkeyedContainer(forKey: .tiles)
        for t in tiles {
            var c = list.nestedContainer(keyedBy: TileKeys.self)
            try c.encode(t.corners.flatMap { [$0.x, $0.y] }, forKey: .c)
            try c.encode(t.paint, forKey: .p)
            if t.stone { try c.encode(1, forKey: .s) }
        }
    }
}

/// Finds the tile under a point quickly: tiles bucketed by their bounds on a coarse grid.
nonisolated public struct TileIndex: Sendable {
    private let cell: Float
    private let columns: Int, rows: Int
    private let buckets: [[Int]]
    private let tiles: [Mosaic.Tile]

    public init(_ mosaic: Mosaic) {
        tiles = mosaic.tiles
        let area = mosaic.width * mosaic.height / Float(max(mosaic.tiles.count, 1))
        cell = max(area.squareRoot() * 2, 1)
        columns = max(Int((mosaic.width / cell).rounded(.up)), 1)
        rows = max(Int((mosaic.height / cell).rounded(.up)), 1)
        var b = [[Int]](repeating: [], count: columns * rows)
        for (i, t) in mosaic.tiles.enumerated() {
            let (lo, hi) = t.bounds
            let c0 = Swift.max(Int(lo.x / cell), 0), c1 = Swift.min(Int(hi.x / cell), columns - 1)
            let r0 = Swift.max(Int(lo.y / cell), 0), r1 = Swift.min(Int(hi.y / cell), rows - 1)
            guard c0 <= c1, r0 <= r1 else { continue }
            for r in r0...r1 { for c in c0...c1 { b[r * columns + c].append(i) } }
        }
        buckets = b
    }

    /// The tile containing `p`, or the nearest one whose centre is within `slop` units of it
    /// (a fingertip lands in a joint as often as on a tile).
    public func tile(at p: SIMD2<Float>, slop: Float = 0) -> Int? {
        let c = Int(p.x / cell), r = Int(p.y / cell)
        guard c >= 0, r >= 0, c < columns, r < rows else { return nil }
        var best: (Int, Float)?
        for dr in -1...1 { for dc in -1...1 {
            let cc = c + dc, rr = r + dr
            guard cc >= 0, rr >= 0, cc < columns, rr < rows else { continue }
            for i in buckets[rr * columns + cc] {
                if tiles[i].contains(p) { return i }
                let d = length(tiles[i].centre - p)
                if d <= slop, d < (best?.1 ?? .infinity) { best = (i, d) }
            }
        } }
        return best?.0
    }

    /// The tiles in the grid cells the rectangle meets: a superset of those on screen, the ones worth
    /// drawing.
    public func tiles(in lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> [Int] {
        let c0 = Swift.max(Int(lo.x / cell), 0), c1 = Swift.min(Int(hi.x / cell), columns - 1)
        let r0 = Swift.max(Int(lo.y / cell), 0), r1 = Swift.min(Int(hi.y / cell), rows - 1)
        guard c0 <= c1, r0 <= r1 else { return [] }
        var seen = Set<Int>(), out: [Int] = []
        for r in r0...r1 { for c in c0...c1 { for i in buckets[r * columns + c] where seen.insert(i).inserted { out.append(i) } } }
        return out
    }
}

@inline(__always) nonisolated private func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }
