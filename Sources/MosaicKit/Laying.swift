/// Laying a row: a mosaicist sets a row of tesserae in one movement along it, so the painter can
/// drag along a row and set every tile of the paint in hand that the finger passes over.
nonisolated extension TileIndex {
    /// The tiles a stroke from `a` to `b` passes over, in the order it meets them, sampled every
    /// `step` units (a fraction of the smallest tile, so a fast stroke skips none). The point `a`
    /// itself is not sampled (it ended the stroke's last piece), though the tile it is on usually is.
    public func tiles(along a: SIMD2<Float>, _ b: SIMD2<Float>, step: Float, slop: Float = 0) -> [Int] {
        let d = b - a, length = (d * d).sum().squareRoot()
        let n = Swift.max(Int((length / Swift.max(step, 0.01)).rounded(.up)), 1)
        var out: [Int] = []
        for k in 1...n {
            let p = a + d * (Float(k) / Float(n))
            if let i = tile(at: p, slop: slop), out.last != i, !out.contains(i) { out.append(i) }
        }
        return out
    }
}

nonisolated extension Setting {
    /// The tiles a stroke lays: of those it passed over, the ones not yet set that take `paint`,
    /// each once, in order.
    public func laying(_ passed: [Int], with paint: Int, in mosaic: Mosaic) -> [Int] {
        var seen = Set<Int>()
        return passed.filter {
            mosaic.tiles.indices.contains($0) && mosaic.tiles[$0].paint == paint && !isSet($0) && seen.insert($0).inserted
        }
    }

    /// The unset tile of `paint` nearest to `point`, for setting without aiming (VoiceOver).
    public func nearestUnset(of paint: Int, to point: SIMD2<Float>, in mosaic: Mosaic) -> Int? {
        var best: (Int, Float)?
        for (i, t) in mosaic.tiles.enumerated() where t.paint == paint && !isSet(i) {
            let v = t.centre - point, d = (v * v).sum()
            if d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }
}
