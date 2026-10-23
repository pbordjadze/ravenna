nonisolated extension MosaicEngine {
    // The cartoon's strokes: a mask thinned to one-pixel lines, the lines walked into chains, and the
    // chains that continue one another linked (the prototype's skeletonize, chains and link).

    nonisolated enum Strokes {
        /// Zhang and Suen's thinning (1984) as `skimage.morphology.skeletonize` runs it in 2D: border
        /// pixels peeled in two alternating sub-iterations until none can go, leaving lines one pixel
        /// wide. Which pixels may go is scikit-image's table (`_fast_skeletonize`, BSD-3-Clause), by
        /// the neighbours NW 1, N 2, NE 4, E 8, SE 16, S 32, SW 64, W 128: 1 in the first
        /// sub-iteration, 2 in the second, 3 in either.
        static let thinningTable: [UInt8] = [
            0, 0, 0, 1, 0, 0, 1, 3, 0, 0, 3, 1, 1, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 2, 0, 3, 0, 3, 3,
            0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 3, 0, 2, 2,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            2, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 3, 0, 2, 0,
            0, 0, 3, 1, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
            3, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            2, 3, 1, 3, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            2, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 0, 1, 0, 0, 0, 0, 2, 2, 0, 0, 2, 0, 0, 0,
        ]

        static func thin(_ m: [UInt8], width w: Int, height h: Int) -> [UInt8] {
            let s = w + 2
            var img = [UInt8](repeating: 0, count: s * (h + 2))
            var live: [Int] = []
            for y in 0..<h {
                for x in 0..<w where m[y * w + x] != 0 {
                    let i = (y + 1) * s + x + 1
                    img[i] = 1; live.append(i)
                }
            }
            // The neighbours as the table weighs them: NW, N, NE, E, SE, S, SW, W.
            let offsets = [-s - 1, -s, -s + 1, 1, s + 1, s, s - 1, -1]
            let table = thinningTable
        var doomed: [Int] = []
            var changed = true
            while changed {
                changed = false
                for pass in 0..<2 {
                    doomed.removeAll(keepingCapacity: true)
                    img.withUnsafeBufferPointer { im in
                        for i in live where im[i] != 0 {
                            var code = 0
                            for k in 0..<8 where im[i + offsets[k]] != 0 { code |= 1 << k }
                            if table[code] & UInt8(1 << pass) != 0 { doomed.append(i) }
                        }
                    }
                    if !doomed.isEmpty {
                        changed = true
                        for i in doomed { img[i] = 0 }
                    }
                }
                live.removeAll { img[$0] == 0 }
            }
            var out = [UInt8](repeating: 0, count: w * h)
            for i in live {
                let x = i % s - 1, y = i / s - 1
                out[y * w + x] = 1
            }
            return out
        }

        /// The prototype's `chains`: a skeleton walked from node to node (pixels with other than two
        /// neighbours), and round its loops, into chains of pixel positions. Neighbours are the four
        /// beside a pixel and the diagonals not already reached through one of those.
        static func chains(_ skeleton: [UInt8], width w: Int, height h: Int) -> [[SIMD2<Double>]] {
            let s = w + 2
            var on = [Bool](repeating: false, count: s * (h + 2))
            var pixels: [Int] = []
            for y in 0..<h {
                for x in 0..<w where skeleton[y * w + x] != 0 {
                    let i = (y + 1) * s + x + 1
                    on[i] = true; pixels.append(i)
                }
            }
            // Directions in the prototype's order: (1,0) (−1,0) (0,1) (0,−1) (1,1) (1,−1) (−1,1) (−1,−1).
            let dx = [1, -1, 0, 0, 1, 1, -1, -1], dy = [0, 0, 1, -1, 1, -1, 1, -1]
            let offset = (0..<8).map { dy[$0] * s + dx[$0] }
            let opposite = [1, 0, 3, 2, 7, 6, 5, 4]
            func neighbours(_ i: Int) -> [(Int, Int)] {
                var out: [(Int, Int)] = []
                for d in 0..<4 where on[i + offset[d]] { out.append((i + offset[d], d)) }
                for d in 4..<8 where on[i + offset[d]] && !on[i + dx[d]] && !on[i + dy[d] * s] {
                    out.append((i + offset[d], d))
                }
                return out
            }
            var degree = [UInt8](repeating: 0, count: on.count)
            var nodes: [Int] = []
            for i in pixels {
                let n = neighbours(i).count
                degree[i] = UInt8(n)
                if n != 2 { nodes.append(i) }
            }
            var seen = [UInt8](repeating: 0, count: on.count)
            func point(_ i: Int) -> SIMD2<Double> { SIMD2(Double(i % s - 1), Double(i / s - 1)) }
            var out: [[SIMD2<Double>]] = []
            for n in nodes + pixels {
                for (q, d) in neighbours(n) where seen[n] & (1 << d) == 0 {
                    var path = [point(n), point(q)]
                    seen[n] |= 1 << d; seen[q] |= 1 << opposite[d]
                    var prev = n, cur = q
                    while degree[cur] == 2 {
                        guard let (r, e) = neighbours(cur).first(where: { $0.0 != prev && seen[cur] & (1 << $0.1) == 0 }) else { break }
                        seen[cur] |= 1 << e; seen[r] |= 1 << opposite[e]
                        path.append(point(r))
                        prev = cur; cur = r
                    }
                    out.append(path)
                }
            }
            return out
        }

        /// The prototype's `link`: chains of six or more points, joined end to end, nearest first, where
        /// the gap is under `reach` and both ends and the gap run the same way (every cosine over `cosmin`).
        static func link(_ chains: [[SIMD2<Double>]], reach: Double, cosmin: Double = 0.6) -> [[SIMD2<Double>]] {
            var cs = chains.filter { $0.count >= 6 }
            func tangent(_ c: [SIMD2<Double>], atEnd: Bool) -> SIMD2<Double> {
                let k = Swift.min(c.count - 1, 12)
                return atEnd ? c[c.count - 1] - c[c.count - 1 - k] : c[0] - c[k]
            }
            func unit(_ v: SIMD2<Double>) -> SIMD2<Double> { v / ((v.x * v.x + v.y * v.y).squareRoot() + 1e-9) }
            while true {
                // Each end: where it is, its chain, which end, its outward direction.
                struct End { var p: SIMD2<Double>; var chain: Int; var atEnd: Bool; var out: SIMD2<Double> }
                var ends: [End] = []
                ends.reserveCapacity(cs.count * 2)
                for (i, c) in cs.enumerated() {
                    ends.append(End(p: c[0], chain: i, atEnd: false, out: unit(tangent(c, atEnd: false))))
                    ends.append(End(p: c[c.count - 1], chain: i, atEnd: true, out: unit(tangent(c, atEnd: true))))
                }
                let order = ends.indices.sorted { ends[$0].p.x != ends[$1].p.x ? ends[$0].p.x < ends[$1].p.x : $0 < $1 }
                var best: (d: Double, a: Int, b: Int)?
                for (oi, ia) in order.enumerated() {
                    var oj = oi + 1
                    while oj < order.count, ends[order[oj]].p.x - ends[ia].p.x <= reach {
                        let ib = order[oj]
                        oj += 1
                        // The prototype's pairs come lower index first.
                        let (a, b) = ia < ib ? (ends[ia], ends[ib]) : (ends[ib], ends[ia])
                        guard a.chain != b.chain else { continue }
                        let gap = b.p - a.p
                        let d = (gap.x * gap.x + gap.y * gap.y).squareRoot()
                        guard d <= reach, d >= 1e-6 else { continue }
                        let ti = a.out, tj = -b.out, gu = gap / d
                        let c1 = ti.x * gu.x + ti.y * gu.y, c2 = tj.x * gu.x + tj.y * gu.y, c3 = ti.x * tj.x + ti.y * tj.y
                        let lo = Swift.min(ia, ib), hi = Swift.max(ia, ib)
                        if Swift.min(c1, c2, c3) > cosmin {
                            if let b0 = best, !(d < b0.d || (d == b0.d && (lo, hi) < (b0.a, b0.b))) { continue }
                            best = (d, lo, hi)
                        }
                    }
                }
                guard let found = best else { return cs }
                let ea = ends[found.a], eb = ends[found.b]
                let a = ea.atEnd ? cs[ea.chain] : cs[ea.chain].reversed()
                let b = eb.atEnd ? cs[eb.chain].reversed() : cs[eb.chain]
                var next = cs.indices.filter { $0 != ea.chain && $0 != eb.chain }.map { cs[$0] }
                next.append(a + b)
                cs = next
            }
        }
    }
}
