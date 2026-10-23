/// The gold ground (an option): the picture's background laid in gold smalti, as behind the figures
/// at Ravenna and in the icons. The background is found from the picture's top and upper sides:
/// the tiles there in the edge's commonest paints, flooded inward through touching tiles of a
/// colour close to their neighbour's (so a gradient is followed), stopped by the outlines' rows
/// and never into a face. Plain Swift, tested on Linux.
nonisolated extension Mosaic {
    /// Smalti gold, as `Theme.gold`: what `TileColor.isGold` knows as gold.
    public static let groundGold = SIMD3<Float>(0.788, 0.635, 0.290)

    /// The background's tiles, ascending.
    public func background() -> [Int] {
        guard !tiles.isEmpty else { return [] }
        let side = (width * height / Float(tiles.count)).squareRoot()
        let near = side * 0.75
        // Seeds: tiles on the top edge, and on the sides' upper two thirds.
        let seeds = tiles.indices.filter { i in
            let t = tiles[i], (lo, hi) = t.bounds
            guard !t.stone else { return false }
            return lo.y < near || (hi.y < height * 2 / 3 && (lo.x < near || hi.x > width - near))
        }
        guard !seeds.isEmpty else { return [] }
        var counts = [Int](repeating: 0, count: palette.count)
        for i in seeds { counts[tiles[i].paint] += 1 }
        // The ground's paints: the edge's commonest, until they cover three quarters of it (a
        // gradient's several shades as well as one flat colour), each on at least 1 in 25 of it.
        var ground = Set<Int>(), covered = 0
        for p in palette.indices.sorted(by: { counts[$0] > counts[$1] }) {
            guard covered * 4 < seeds.count * 3, counts[p] * 25 >= seeds.count else { break }
            covered += counts[p]
            if !TileColor.isGold(palette[p]) { ground.insert(p) }
        }
        guard !ground.isEmpty else { return [] }
        let lab = palette.map(OKLab.from)
        func takes(_ i: Int) -> Bool {
            let t = tiles[i]
            return !t.stone && t.stage != .feature && t.stage != .eye && t.stage != .strand && !TileColor.isGold(palette[t.paint])
        }
        func alike(_ a: Int, _ b: Int) -> Bool {
            let d = lab[tiles[a].paint] - lab[tiles[b].paint]
            return (d * d).sum() < 0.06 * 0.06
        }

        let index = TileIndex(self), gap = side * 0.3
        var inGround = [Bool](repeating: false, count: tiles.count)
        var queue = seeds.filter { ground.contains(tiles[$0].paint) && takes($0) }
        for i in queue { inGround[i] = true }
        while let i = queue.popLast() {
            let (lo, hi) = tiles[i].bounds
            let a = lo - SIMD2(gap, gap), b = hi + SIMD2(gap, gap)
            for j in index.tiles(in: a, b) where !inGround[j] && takes(j) && alike(i, j) {
                let (lo2, hi2) = tiles[j].bounds
                guard lo2.x <= b.x, hi2.x >= a.x, lo2.y <= b.y, hi2.y >= a.y else { continue }
                inGround[j] = true
                queue.append(j)
            }
        }
        return tiles.indices.filter { inGround[$0] }
    }

    /// The mosaic with its background laid in gold: those tiles take one new gold paint, the last,
    /// and any paint left with no tiles is dropped (the others keep their order). Tile indices
    /// don't change, so the painter's setting carries over.
    public func goldGround() -> Mosaic {
        let back = background()
        guard !back.isEmpty else { return self }
        var out = self
        let gold = palette.count
        out.palette.append(Self.groundGold)
        for i in back { out.tiles[i].paint = gold }
        // Drop paints nothing uses now, renumbering the rest.
        var used = [Bool](repeating: false, count: out.palette.count)
        for t in out.tiles { used[t.paint] = true }
        var map = [Int](repeating: -1, count: out.palette.count), kept: [SIMD3<Float>] = []
        for p in out.palette.indices where used[p] { map[p] = kept.count; kept.append(out.palette[p]) }
        out.palette = kept
        for i in out.tiles.indices { out.tiles[i].paint = map[out.tiles[i].paint] }
        return out
    }
}
