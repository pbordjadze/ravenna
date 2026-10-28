#if canImport(MosaicKit)
import MosaicKit
#endif

nonisolated extension MosaicEngine {
    /// What the painter drew on a mosaic in Refine, before setting it: a line the tiles' rows
    /// follow, the photo's contours rubbed out, or the gold ground brushed on or off. Kept in the
    /// recipe in the order drawn (`Recipe.marks`), in the panel's unit square (x right, y down), so
    /// the mosaic is made again as it was, at any size.
    nonisolated public struct Mark: Sendable, Hashable, Codable {
        nonisolated public enum Kind: String, Sendable, Hashable, CaseIterable {
            /// A line the rows follow: drawn into the contours, an outline as the photo's are.
            case line
            /// The photo's contours rubbed out under it: no outline there.
            case unline
            /// The tiles under it laid in the gold ground.
            case gold
            /// The gold ground taken off the tiles under it: they keep the picture's paint.
            case ungold

            /// Whether it changes where the tiles go (the engine lays the mosaic again), or only
            /// their paint, laid on as the ground is.
            public var movesTiles: Bool { self == .line || self == .unline }
        }

        public var kind: Kind
        /// The stroke's width, as a share of the panel's long side.
        public var width: Double
        /// Its path in the panel's unit square; a single point is a dab.
        public var points: [SIMD2<Double>]

        /// A mark as `meta.json` keeps it, so the mosaic laid now is the one made again: its width
        /// rounded to 1/100,000 and at most `maximumWidth`, its points to 1/10,000 of the panel
        /// (finer than a pixel of the largest mosaic) and kept within a panel's width of it.
        public init(kind: Kind, width: Double, points: [SIMD2<Double>]) {
            self.kind = kind
            self.width = Swift.min((width * 100_000).rounded() / 100_000, Self.maximumWidth)
            self.points = points.map { p in
                let q = (p * 10_000).rounded(.toNearestOrAwayFromZero) / 10_000
                return SIMD2(Swift.min(Swift.max(q.x, -1), 2), Swift.min(Swift.max(q.y, -1), 2))
            }
        }

        /// A mark as given, unrounded: the stroke scaled to pixels or canvas units, or a piece of it.
        init(exactly kind: Kind, width: Double, points: [SIMD2<Double>]) {
            self.kind = kind; self.width = width; self.points = points
        }

        /// The widest stroke kept: half the panel.
        public static let maximumWidth = 0.5

        /// A drawn line shorter than this (a share of the panel's long side) is a tap, not a line:
        /// too short to lay a row along.
        public static let shortestLine = 0.03

        /// The path's length in the panel's unit square.
        public var length: Double {
            zip(points, points.dropFirst()).reduce(0) { $0 + (($1.1 - $1.0) * ($1.1 - $1.0)).sum().squareRoot() }
        }

        /// The stroke with points that add less than `tolerance` (in the panel's unit square) to its
        /// shape left out (Ramer–Douglas–Peucker): a finger's drag is hundreds of points.
        public func simplified(tolerance: Double = 0.0015) -> Mark {
            guard points.count > 2 else { return self }
            var keep = [Bool](repeating: false, count: points.count)
            keep[0] = true; keep[points.count - 1] = true
            var spans = [(0, points.count - 1)]
            while let (a, b) = spans.popLast() {
                guard b > a + 1 else { continue }
                let segment = Mark(exactly: kind, width: width, points: [points[a], points[b]])
                var far = a, most = 0.0
                for i in (a + 1)..<b {
                    let d = segment.distanceSquared(to: points[i])
                    if d > most { most = d; far = i }
                }
                if most > tolerance * tolerance {
                    keep[far] = true
                    spans.append((a, far)); spans.append((far, b))
                }
            }
            return Mark(kind: kind, width: width, points: points.indices.filter { keep[$0] }.map { points[$0] })
        }

        private enum CodingKeys: String, CodingKey { case kind, width, points }

        /// `{"kind": "line", "width": 0.004, "points": [x0, y0, x1, y1, …]}`. A mark that doesn't
        /// read (an unknown kind, a width or point that isn't a number) fails alone: the recipe
        /// passes it over (`Recipe.init(from:)`).
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let kind = Kind(rawValue: try c.decode(String.self, forKey: .kind)) else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown mark")
            }
            let width = try c.decode(Double.self, forKey: .width)
            let flat = try c.decode([Double].self, forKey: .points)
            guard width.isFinite, width > 0, !flat.isEmpty, flat.count.isMultiple(of: 2), flat.allSatisfy(\.isFinite) else {
                throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "Malformed mark")
            }
            self.init(kind: kind, width: width, points: stride(from: 0, to: flat.count, by: 2).map { SIMD2(flat[$0], flat[$0 + 1]) })
        }

        /// As made (`init` rounds): a simplified stroke costs a few hundred bytes in `meta.json`.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind.rawValue, forKey: .kind)
            try c.encode(width, forKey: .width)
            try c.encode(points.flatMap { [$0.x, $0.y] }, forKey: .points)
        }

        /// The square of the distance from `p` to the stroke's path.
        func distanceSquared(to p: SIMD2<Double>) -> Double {
            guard let first = points.first else { return .infinity }
            var best = ((p - first) * (p - first)).sum()
            for (a, b) in zip(points, points.dropFirst()) {
                let ab = b - a, len = (ab * ab).sum()
                let t = len > 0 ? Swift.min(Swift.max(((p - a) * ab).sum() / len, 0), 1) : 0
                let q = a + ab * t
                best = Swift.min(best, ((p - q) * (p - q)).sum())
            }
            return best
        }

        /// The stroke's bounds, grown by `pad`: (min, max).
        func bounds(pad: Double) -> (SIMD2<Double>, SIMD2<Double>) {
            var lo = SIMD2<Double>(.infinity, .infinity), hi = -lo
            for p in points { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            return (lo - SIMD2(pad, pad), hi + SIMD2(pad, pad))
        }

        /// The stroke in a plane of `width` by `height` (pixels or canvas units): its path scaled,
        /// its half-width in the same units.
        func scaled(width: Double, height: Double) -> (mark: Mark, radius: Double) {
            let k = SIMD2(width, height)
            return (Mark(exactly: kind, width: self.width, points: points.map { $0 * k }),
                    self.width * Swift.max(width, height) / 2)
        }

        /// The tiles of `mosaic` whose centre is under the stroke, ascending.
        public func tiles(of mosaic: Mosaic) -> [Int] {
            let (m, r) = scaled(width: Double(mosaic.width), height: Double(mosaic.height))
            let (lo, hi) = m.bounds(pad: r), r2 = r * r
            return mosaic.tiles.indices.filter { i in
                let c = SIMD2<Double>(mosaic.tiles[i].centre)
                guard c.x >= lo.x, c.y >= lo.y, c.x <= hi.x, c.y <= hi.y else { return false }
                return m.distanceSquared(to: c) <= r2
            }
        }

        /// The stroke drawn into `contours` (0...1, `width` by `height`, row-major): a line raised to
        /// an outline's strength along its path (full in its middle, half at its edge, fading over
        /// as far again), or the contours rubbed out under it (gone within its width, back over a
        /// half-width more). A gold mark changes nothing here. Each segment measures only its own
        /// box, into the distance to the nearest one, so a long slow stroke costs no more than a
        /// quick one.
        func draw(into contours: inout [Float], width: Int, height: Int) {
            guard kind.movesTiles, width > 0, height > 0, contours.count == width * height, !points.isEmpty else { return }
            let (m, scaledRadius) = scaled(width: Double(width), height: Double(height))
            // A line stays an outline however small the draft: the engine doubles the contours and
            // blurs them (σ 2) before its cut, which takes a thinner one away.
            let r = kind == .line ? Swift.max(scaledRadius, Self.thinnestLine) : scaledRadius
            let reach = kind == .line ? 2 * r : 1.5 * r
            func clampX(_ v: Double) -> Int { Int(Swift.min(Swift.max(v, 0), Double(width - 1))) }
            func clampY(_ v: Double) -> Int { Int(Swift.min(Swift.max(v, 0), Double(height - 1))) }
            let (lo, hi) = m.bounds(pad: reach)
            guard hi.x >= 0, hi.y >= 0, lo.x <= Double(width), lo.y <= Double(height) else { return }
            let bx0 = clampX(lo.x.rounded(.down)), bx1 = clampX(hi.x.rounded(.up))
            let by0 = clampY(lo.y.rounded(.down)), by1 = clampY(hi.y.rounded(.up))
            let bw = bx1 - bx0 + 1
            var nearest = [Double](repeating: .infinity, count: bw * (by1 - by0 + 1))
            let segments = m.points.count == 1 ? [(m.points[0], m.points[0])] : Array(zip(m.points, m.points.dropFirst()))
            for (a, b) in segments {
                let piece = Mark(exactly: kind, width: self.width, points: a == b ? [a] : [a, b])
                let (slo, shi) = piece.bounds(pad: reach)
                guard shi.x >= 0, shi.y >= 0, slo.x <= Double(width), slo.y <= Double(height) else { continue }
                for y in clampY(slo.y.rounded(.down))...clampY(shi.y.rounded(.up)) {
                    for x in clampX(slo.x.rounded(.down))...clampX(shi.x.rounded(.up)) {
                        let d = piece.distanceSquared(to: SIMD2(Double(x) + 0.5, Double(y) + 0.5))
                        let j = (y - by0) * bw + (x - bx0)
                        if d < nearest[j] { nearest[j] = d }
                    }
                }
            }
            for y in by0...by1 {
                for x in bx0...bx1 {
                    let d = nearest[(y - by0) * bw + (x - bx0)].squareRoot()
                    guard d < reach else { continue }
                    let i = y * width + x
                    if kind == .line {
                        let v = d <= r ? 1 - 0.5 * (d / r) * (d / r) : 0.5 * (reach - d) / (reach - r)
                        contours[i] = Swift.max(contours[i], Float(v))
                    } else {
                        contours[i] *= Float(d <= r ? 0 : (d - r) / (reach - r))
                    }
                }
            }
        }

        /// A drawn line's least half-width in the contours' pixels.
        static let thinnestLine = 1.5

        /// The stroke moved from one panel of a photo to another (each `Panel.rect`'s unit square,
        /// in a photo `photoWidth` by `photoHeight`), keeping its place and size on the photo.
        func reframed(from old: (x: Double, y: Double, width: Double, height: Double),
                      to new: (x: Double, y: Double, width: Double, height: Double),
                      photoWidth: Double, photoHeight: Double) -> Mark {
            guard new.width > 0, new.height > 0 else { return self }
            let moved = points.map { p in
                SIMD2((old.x + p.x * old.width - new.x) / new.width, (old.y + p.y * old.height - new.y) / new.height)
            }
            let oldLong = Swift.max(old.width * photoWidth, old.height * photoHeight)
            let newLong = Swift.max(new.width * photoWidth, new.height * photoHeight)
            let w = newLong > 0 ? width * oldLong / newLong : width
            return Mark(kind: kind, width: Swift.min(w, Self.maximumWidth), points: moved)
        }
    }
}

nonisolated extension MosaicEngine.Recipe {
    /// What the engine's tiles depend on: this recipe without what is laid on after (the ground
    /// and the gold marks), so mosaics kept by it serve every ground.
    public var forTiles: Self {
        var r = self
        r.ground = .picture
        r.marks = marks.filter(\.kind.movesTiles)
        return r
    }

    /// The marks that move tiles drawn into `contours` (the panel's contour map, `width` by
    /// `height`), in the order they were made.
    public func mark(contours: inout [Float], width: Int, height: Int) {
        for m in marks where m.kind.movesTiles { m.draw(into: &contours, width: width, height: height) }
    }

    /// The tiles of `mosaic` in the gold ground: the background the ground finds when it is gold,
    /// then each gold mark's tiles added or taken off in turn.
    public func goldTiles(of mosaic: Mosaic) -> [Int] {
        var gold = Set(ground == .gold ? mosaic.background() : [])
        for m in marks where !m.kind.movesTiles {
            let under = m.tiles(of: mosaic)
            if m.kind == .gold { gold.formUnion(under) } else { gold.subtract(under) }
        }
        return gold.sorted()
    }

    /// This recipe with its marks moved from `old`'s panel to its own on a photo `photoWidth` by
    /// `photoHeight` (any units), so what was drawn stays on the same part of the photo when the
    /// panel changes or moves.
    public func reframingMarks(from old: Self, photoWidth: Double, photoHeight: Double) -> Self {
        guard !marks.isEmpty else { return self }
        let a = old.panel.rect(width: photoWidth, height: photoHeight, centre: old.centre)
        let b = panel.rect(width: photoWidth, height: photoHeight, centre: centre)
        guard a != b else { return self }
        var r = self
        r.marks = marks.map { $0.reframed(from: a, to: b, photoWidth: photoWidth, photoHeight: photoHeight) }
        return r
    }
}
