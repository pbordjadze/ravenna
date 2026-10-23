#if canImport(MosaicKit)
import MosaicKit
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Ravenna's mosaic maker: a photo, its contour map and its faces' features in, a `Mosaic` out.
/// Ported from `prototype/mosaic_faces.py` as the sketchbook runs it (GROUT=2 TIGHT=1, FEATURES):
/// the drawing's strong lines laid first as rows of dark tiles, the faces' features as their own
/// pieces, then rows that echo them, the photo's colour edges and the picture's edge, the gaps
/// filled with pieces cut to the space, and every tile's colour gathered into a few paints.
///
/// Plain Swift, no dependencies beyond MosaicKit's types, and deterministic: the same input makes
/// the same mosaic on any machine.
nonisolated public enum MosaicEngine {
    nonisolated public struct Settings: Sendable, Equatable {
        /// Tile pitch in pixels of the working image (twice the photo): the script's S.
        public var pitch: Float = 30
        /// The pitch in a face: FINE.
        public var facePitch: Float = 17
        /// How many paints: K.
        public var paints: Int = 18
        /// The contour map's level for a strong line: CUT.
        public var cut: Float = 0.72
        /// The same in a face: CUT_FINE.
        public var faceCut: Float = 0.45
        /// The joint between tiles, in working pixels: GROUT (the tight set).
        public var grout: Int = 2
        public init() {}
    }

    /// A photo in sRGB 0...1, row-major, at its working size (the caller scales it, e.g. long side 1024).
    nonisolated public struct Photo: Sendable {
        public var width: Int
        public var height: Int
        public var rgb: [SIMD3<Float>]
        public init(width: Int, height: Int, rgb: [SIMD3<Float>]) {
            self.width = width; self.height = height; self.rgb = rgb
        }
    }

    /// One face's features in the photo's pixels, as `sketchbook/features.py` writes them.
    nonisolated public struct Face: Sendable, Codable, Equatable {
        /// x0, y0, x1, y1.
        public var box: [Float]
        /// Each [cx, cy, iris r, pupil r].
        public var eyes: [[Float]]
        public var lines: [Line]

        nonisolated public struct Line: Sendable, Codable, Equatable {
            /// dark | mid | tone | eye | lips
            public var kind: String
            /// Each [x, y].
            public var pts: [[Float]]
            public init(kind: String, pts: [[Float]]) { self.kind = kind; self.pts = pts }
        }

        public init(box: [Float], eyes: [[Float]] = [], lines: [Line] = []) {
            self.box = box; self.eyes = eyes; self.lines = lines
        }

        private enum CodingKeys: String, CodingKey { case box, eyes, lines }

        public init(from decoder: any Decoder) throws {
            let k = try decoder.container(keyedBy: CodingKeys.self)
            box = try k.decode([Float].self, forKey: .box)
            eyes = try k.decodeIfPresent([[Float]].self, forKey: .eyes) ?? []
            lines = try k.decodeIfPresent([Line].self, forKey: .lines) ?? []
        }
    }

    /// Input that can't make a mosaic.
    nonisolated public enum InputError: Error, Equatable {
        /// The photo is empty or its pixels aren't width × height.
        case photoSize
        /// The contour map isn't at the photo's size.
        case contourSize
    }

    /// What a run did, for tools: each stage's wall time and the tiles laid by its end; which tiles
    /// are strands (rows on the drawing's lines and the features' dark rows) and which feature each
    /// tile sets, if any (dark, mid, tone, eye, lips).
    nonisolated public struct Trace: Sendable {
        nonisolated public struct Stage: Sendable {
            public var name: String
            public var seconds: Double
            public var tiles: Int
        }
        public var stages: [Stage] = []
        /// One per tile of the mosaic made.
        public var strand: [Bool] = []
        /// One per tile of the mosaic made.
        public var feature: [String?] = []
        public init() {}
    }

    /// contours: the HED contour map at the photo's size, 0...1, row-major. faces: may be empty (then
    /// no face boxes, no fine pitch, no eyes). `cancel` is polled between stages.
    public static func make(photo: Photo, contours: [Float], faces: [Face], settings: Settings = Settings(),
                            cancel: () -> Bool = { false }) throws -> Mosaic {
        var trace = Trace()
        return try make(photo: photo, contours: contours, faces: faces, settings: settings, cancel: cancel, trace: &trace)
    }

    /// `make`, recording each stage's time and the tiles that are strands in `trace`.
    public static func make(photo: Photo, contours: [Float], faces: [Face], settings: Settings = Settings(),
                            cancel: () -> Bool, trace: inout Trace) throws -> Mosaic {
        guard photo.width > 0, photo.height > 0, photo.rgb.count == photo.width * photo.height else {
            throw InputError.photoSize
        }
        guard contours.count == photo.width * photo.height else { throw InputError.contourSize }
        let run = Run(photo: photo, contours: contours, faces: faces, settings: settings)
        return try run.make(cancel: cancel, trace: &trace)
    }
}

nonisolated extension MosaicEngine {
    /// One mosaic in the making, at twice the photo's size (the script's SCALE).
    nonisolated final class Run {
        static let scale = 2

        let s: Double, fine: Double, g: Int, paints: Int
        let cut: Float, faceCut: Float
        let w0: Int, h0: Int, W: Int, H: Int
        let boxes: [[Float]], eyes: [[Float]], lines: [Face.Line]
        /// The eyes' openings, in working pixels.
        let eyeRings: [[SIMD2<Double>]]
        var red: [Float], green: [Float], blue: [Float]
        var draw: [Float]
        var pitchMap: Plane
        var layout: Layout

        init(photo: Photo, contours: [Float], faces: [Face], settings: Settings) {
            g = Swift.max(settings.grout, 0)
            s = Swift.max(Double(settings.pitch), Double(g) + 2)
            fine = Swift.max(Double(settings.facePitch), Double(g) + 2)
            paints = Swift.max(settings.paints, 1)
            cut = settings.cut; faceCut = settings.faceCut
            w0 = photo.width; h0 = photo.height
            W = w0 * Self.scale; H = h0 * Self.scale
            boxes = faces.map(\.box).filter { $0.count >= 4 }
            eyes = faces.flatMap(\.eyes).filter { $0.count >= 3 }
            lines = faces.flatMap(\.lines)
            eyeRings = lines.filter { $0.kind == "eye" }.map { Run.points($0.pts) }
            let rgb = photo.rgb
            func channel(_ c: Int) -> [Float] {
                Resize.upscale2x(rgb.map { $0[c] }, width: photo.width, height: photo.height).map { Swift.min(Swift.max($0, 0), 1) }
            }
            red = channel(0); green = channel(1); blue = channel(2)
            // The script resizes the 8-bit map, so the drawing comes in 8-bit steps.
            draw = Resize.bilinear(contours, width: photo.width, height: photo.height, to: W, H)
                .map { ($0 * 255).rounded() / 255 }
            pitchMap = Plane(width: W, height: H, value: Float(s))
            layout = Layout(width: W, height: H, grout: g, pitchMap: [])
        }

        /// Feature points in working pixels.
        static func points(_ pts: [[Float]]) -> [SIMD2<Double>] {
            pts.filter { $0.count >= 2 }.map { SIMD2(Double($0[0]), Double($0[1])) * Double(scale) }
        }

        /// The face boxes in working pixels, as the script slices them.
        func boxMask() -> [UInt8] {
            var m = [UInt8](repeating: 0, count: W * H)
            for b in boxes {
                func cell(_ v: Float, _ n: Int) -> Int {
                    guard v.isFinite else { return 0 }
                    return Swift.min(Swift.max(Int(Swift.max(Swift.min(v * Float(Self.scale), 1e9), -1e9)), 0), n)
                }
                let x0 = cell(b[0], W), y0 = cell(b[1], H), x1 = cell(b[2], W), y1 = cell(b[3], H)
                guard x1 > x0, y1 > y0 else { continue }
                for y in y0..<y1 { for x in x0..<x1 { m[y * W + x] = 1 } }
            }
            return m
        }

        func make(cancel: () -> Bool, trace: inout Trace) throws -> Mosaic {
            let clock = ContinuousClock()
            var last = clock.now
            func lap(_ name: String) throws {
                let now = clock.now, d = now - last
                trace.stages.append(.init(name: name, seconds: Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18,
                                          tiles: layout.pieces.count))
                last = now
                if cancel() { throw CancellationError() }
            }
            let inbox = boxes.isEmpty ? [UInt8](repeating: 0, count: W * H) : boxMask()
            if !boxes.isEmpty {
                let m = Blur.gaussian(Plane(width: W, height: H, pixels: inbox.map { Float($0) }), sigma: s * 1.2)
                pitchMap.pixels = m.pixels.map { Float(s + (fine - s) * Double(Swift.min(Swift.max($0 * 1.4, 0), 1))) }
            }
            layout = Layout(width: W, height: H, grout: g, pitchMap: pitchMap.pixels)
            try lap("upscale")

            let guides = strokes(inbox: inbox)
            try lap("strokes")

            let pupils = features()
            for P in guides {
                lay(row: P, strand: true, minFrac: 0.35, feature: nil)
            }
            try lap("strands")

            let edges = colourEdges()
            try lap("segments")

            var seed = edges
            for i in seed.indices where layout.forbid[i] != 0 { seed[i] = 1 }
            var D = Distance.edt(seed: seed, width: W, height: H)
            for y in 0..<H {
                for x in 0..<W {
                    let border = Float(Swift.min(Swift.min(x, W - 1 - x), Swift.min(y, H - 1 - y)) + g)
                    D[x, y] = Swift.min(D[x, y], border)
                }
            }
            D = Blur.gaussian(D, sigma: 2)
            let around = boxes.isEmpty ? pitchMap : Blur.gaussian(pitchMap, sigma: s)
            var Dn = D
            for i in Dn.pixels.indices { Dn.pixels[i] /= around.pixels[i] }
            try lap("distance")

            rows(Dn)
            try lap("rows")

            gaps(D)
            try lap("gaps")

            layout.pieces += pupils
            for ln in lines where ln.kind == "eye" || ln.kind == "lips" {
                let ring = Run.points(ln.pts)
                for i in layout.pieces.indices where layout.pieces[i].feature == nil && layout.pieces[i].eye == nil {
                    if Polygon.contains(ring, Polygon.mean(layout.pieces[i].poly)) { layout.pieces[i].feature = ln.kind }
                }
            }
            let med = colours()
            try lap("colours")

            let mosaic = palette(med)
            trace.strand = layout.pieces.map(\.strand)
            trace.feature = layout.pieces.map(\.feature)
            try lap("palette")
            return mosaic
        }

        // MARK: The cartoon

        /// The drawing's strong lines as smooth chains, the guides strands are laid along.
        func strokes(inbox: [UInt8]) -> [[SIMD2<Double>]] {
            let blurred = Blur.gaussian(Plane(width: W, height: H, pixels: draw), sigma: 2)
            var strong = [UInt8](repeating: 0, count: W * H)
            for i in strong.indices where blurred.pixels[i] > (inbox[i] != 0 ? faceCut : cut) { strong[i] = 1 }
            strong = Morph.close(strong, width: W, height: H, radius: 2)
            strong = Components.removeSmall(strong, width: W, height: H, maxSize: Int(s * 4))
            let skeleton = Strokes.thin(strong, width: W, height: H)
            let chs = Strokes.chains(skeleton, width: W, height: H)
            let linked = Strokes.link(chs, reach: s * 0.9)
            var guides: [[SIMD2<Double>]] = []
            for P in linked where Double(P.count) >= 2.2 * s {
                guides.append(Blur.smooth(P, sigma: s * 0.35, wrap: false))
            }
            if let path = getenv("MOSAIC_DUMP") {   // DEBUG-DUMP
                let base = String(cString: path)   // DEBUG-DUMP
                func pgm(_ name: String, _ m: [UInt8]) { let f = fopen(base + name, "w")!; fputs("P5\n\(W) \(H)\n255\n", f); _ = m.map { $0 * 255 }.withUnsafeBufferPointer { fwrite($0.baseAddress, 1, $0.count, f) }; fclose(f) }   // DEBUG-DUMP
                pgm("-strong.pgm", strong); pgm("-skel.pgm", skeleton)   // DEBUG-DUMP
                let f = fopen(base + "-guides.json", "w")!   // DEBUG-DUMP
                fputs("{\"chains\": \(chs.count), \"linked\": \(linked.map(\.count)), \"guides\": [" + guides.map { "[" + $0.map { "[\($0.x), \($0.y)]" }.joined(separator: ",") + "]" }.joined(separator: ",") + "]}", f); fclose(f)   // DEBUG-DUMP
                print("chains", chs.count, "linked", linked.count, "guides", guides.count, "strong px", strong.reduce(0) { $0 + Int($1) }, "skel px", skeleton.reduce(0) { $0 + Int($1) })   // DEBUG-DUMP
            }   // DEBUG-DUMP
            // Longest first; the sort keeps the order of equals.
            return guides.indices.sorted { guides[$0].count != guides[$1].count ? guides[$0].count > guides[$1].count : $0 < $1 }
                .map { guides[$0] }
        }

        /// A row of square tiles along a polyline.
        func lay(row P: [SIMD2<Double>], strand: Bool, minFrac: Double, feature: String?) {
            let (pts, _) = layout.resample(P)
            for (i, p) in pts.enumerated() {
                var a = pts[Swift.max(i - 1, 0)], b = pts[Swift.min(i + 1, pts.count - 1)]
                if pts.count == 1 { a = P[0]; b = P[P.count - 1] }
                layout.place(layout.square(p, b - a), strand: strand, minFrac: minFrac, feature: feature)
            }
        }

        /// The part of an iris or pupil inside its eye's opening (all of it when there is none).
        func lidded(_ poly: [SIMD2<Double>]) -> [SIMD2<Double>] {
            let c = Polygon.mean(poly)
            for ring in eyeRings where Polygon.contains(ring, c) {
                return intersect(poly, ring) ?? poly
            }
            return poly
        }

        /// The eyes (each iris one round piece), then the features' rows. Returns the pupils, laid
        /// over their irises once everything else is.
        func features() -> [Layout.Piece] {
            var pupils: [Layout.Piece] = []
            let k = Double(Self.scale)
            for e in eyes {
                let c = SIMD2(Double(e[0]), Double(e[1])) * k, rr = Double(e[2]) * k
                func ring(_ rx: Double, _ ry: Double) -> [SIMD2<Double>] {
                    (0..<28).map { i in
                        let a = 2 * Double.pi * Double(i) / 28
                        return c + SIMD2(rx * cos(a), ry * sin(a))
                    }
                }
                layout.place(lidded(ring(rr, rr)), strand: false, minFrac: 0.1, eye: .iris)
                if e.count > 3 {
                    let px = Double(e[3]) * k, py = Double(e.count > 4 ? e[4] : e[3]) * k
                    pupils.append(Layout.Piece(poly: lidded(ring(px, py)), strand: false, eye: .pupil, feature: nil))
                }
            }
            for ln in lines where ln.kind != "eye" && ln.kind != "lips" {
                let P0 = Run.points(ln.pts)
                guard let last = P0.last else { continue }
                var P: [SIMD2<Double>] = []
                for (a, b) in zip(P0, P0.dropFirst()) {
                    let v = b - a
                    let n = Swift.max(Int((v.x * v.x + v.y * v.y).squareRoot()), 2)
                    for i in 0..<n { P.append(a + v * (Double(i) / Double(n))) }
                }
                P.append(last)
                P = Blur.smooth(P, sigma: fine * 0.2, wrap: false)
                lay(row: P, strand: ln.kind == "dark", minFrac: 0.3, feature: ln.kind)
            }
            return pupils
        }

        // MARK: Rows

        /// The photo's colour regions (k-means of its blurred OKLab), their borders the edges rows echo.
        func colourEdges() -> [UInt8] {
            let sigma = s * 0.12
            let r = Blur.gaussian(Plane(width: W, height: H, pixels: red), sigma: sigma).pixels
            let gr = Blur.gaussian(Plane(width: W, height: H, pixels: green), sigma: sigma).pixels
            let b = Blur.gaussian(Plane(width: W, height: H, pixels: blue), sigma: sigma).pixels
            let ok = FastOKLab()
            let weight = SIMD3<Float>(1, 1.6, 1.6)
            var X = [SIMD3<Float>](repeating: .zero, count: W * H)
            for i in X.indices { X[i] = ok.lab(SIMD3(r[i], gr[i], b[i])) * weight }
            var rng = SplitMix64(seed: 3)
            let sample = rng.sample(X.count, count: 60000).map { X[$0] }
            let km = KMeans.run(sample, k: 8, maxIterations: 30, epsilon: 1e-3, attempts: 3, rng: &rng)
            var seg = [UInt8](repeating: 0, count: W * H)
            for i in X.indices { seg[i] = UInt8(KMeans.nearest(X[i], km.centers)) }
            seg = Morph.median(seg, width: W, height: H, size: 9, levels: Swift.max(km.centers.count, 1))
            let edges = Morph.labelEdges(seg, width: W, height: H)
            return Components.removeSmall(edges, width: W, height: H, maxSize: Int(s * 3))
        }

        /// Rows along the level lines of the distance to everything laid and every colour edge, one
        /// level a pitch apart.
        func rows(_ Dn: Plane) {
            let top = Dn.max
            let base = 0.5 + Double(g) / s
            var k = 0
            var mask = [UInt8](repeating: 0, count: W * H)
            while base + Double(k) < Double(top) {
                let level = Float(base + Double(k))
                for i in mask.indices { mask[i] = Dn.pixels[i] < level ? 1 : 0 }
                var tracer = BorderTracer(mask, width: W, height: H)
                let rings = tracer.all()
                let order = rings.indices.sorted { rings[$0].count != rings[$1].count ? rings[$0].count > rings[$1].count : $0 < $1 }
                for ri in order where rings[ri].count >= 8 {
                    let R = Blur.smooth(rings[ri].map { SIMD2(Double($0.x), Double($0.y)) }, sigma: 4, wrap: true)
                    let (pts, length) = layout.resample(R + [R[0]])
                    guard length >= layout.pitch(R[0]), !pts.isEmpty else { continue }
                    let n = pts.count
                    for i in 0..<n {
                        layout.place(layout.square(pts[i], pts[(i + 1) % n] - pts[(i + n - 1) % n]), strand: false, minFrac: 0.25)
                    }
                }
                k += 1
            }
        }

        /// The gaps: pieces at the centres of the free spaces, turned along the distance's level lines,
        /// a little bigger than a tile so they're cut to the space.
        func gaps(_ D: Plane) {
            let (gy, gx) = Distance.gradient(Blur.gaussian(D, sigma: s * 0.6))
            let window = Int(s)
            for _ in 0..<4 {
                var taken = [UInt8](repeating: 0, count: W * H)
                for y in 0..<H {
                    for x in 0..<W where !layout.inside(x, y) || layout.forbid[y * W + x] != 0 { taken[y * W + x] = 1 }
                }
                let dt = Distance.edt(seed: taken, width: W, height: H)
                let peak = Morph.maxFilter(dt, before: window / 2, after: window - 1 - window / 2)
                var peaks: [Int] = []
                for i in dt.pixels.indices {
                    let v = dt.pixels[i]
                    if v >= 0.3 * (pitchMap.pixels[i] - Float(g)) && v == peak.pixels[i] { peaks.append(i) }
                }
                peaks.sort { dt.pixels[$0] != dt.pixels[$1] ? dt.pixels[$0] > dt.pixels[$1] : $0 < $1 }
                var added = 0
                for i in peaks where layout.forbid[i] == 0 {
                    let x = i % W, y = i / W
                    let t = SIMD2(Double(-gy.pixels[i]), Double(gx.pixels[i])) + 1e-6
                    if layout.place(layout.square(SIMD2(Double(x), Double(y)), t, grow: 1.12), strand: false, minFrac: 0.3) {
                        added += 1
                    }
                }
                if added == 0 { break }
            }
        }

        // MARK: Colours

        /// Each tile's colour in OKLab: its median, with the eyes', features' and strands' own rules;
        /// then a field tile's colour leaning on its neighbours'.
        func colours() -> [SIMD3<Float>] {
            let pieces = layout.pieces
            var med: [SIMD3<Float>] = []
            med.reserveCapacity(pieces.count)
            let luma = SIMD3<Float>(0.2126, 0.7152, 0.0722)
            func brightest(_ px: [SIMD3<Float>], _ q: Double, above: Bool) -> [SIMD3<Float>] {
                var lum = px.map { ($0 * luma).sum() }
                let cutoff = Stats.percentile(&lum, q)
                return px.filter { above ? ($0 * luma).sum() >= cutoff : ($0 * luma).sum() <= cutoff }
            }
            for t in pieces {
                let p = t.poly
                var lo = p[0], hi = p[0]
                for q in p { lo = pointwiseMin(lo, q); hi = pointwiseMax(hi, q) }
                let x0 = Int(lo.x.rounded(.down)), y0 = Int(lo.y.rounded(.down))
                let bw = Int(hi.x.rounded(.up)) + 1 - x0, bh = Int(hi.y.rounded(.up)) + 1 - y0
                var m = [UInt8](repeating: 0, count: Swift.max(bw * bh, 0))
                Polygon.fill(p, origin: SIMD2(Double(x0), Double(y0)), quarter: false, into: &m, width: bw, height: bh)
                var px: [SIMD3<Float>] = [], at: [SIMD2<Int>] = []
                for yy in 0..<bh {
                    let y = y0 + yy
                    guard y >= 0 && y < H else { continue }
                    for xx in 0..<bw where m[yy * bw + xx] != 0 {
                        let x = x0 + xx
                        guard x >= 0 && x < W else { continue }
                        let i = y * W + x
                        px.append(SIMD3(red[i], green[i], blue[i])); at.append(SIMD2(xx, yy))
                    }
                }
                if px.isEmpty {
                    let c = Polygon.mean(p)
                    let i = clampIndex(Int(c.y), H) * W + clampIndex(Int(c.x), W)
                    px = [SIMD3(red[i], green[i], blue[i])]; at = [.zero]
                }
                var c = OKLab.from(Stats.median(px))
                if t.eye == .iris {
                    // The iris's own glass: its ring, outside the pupil and inside the lids' shadow,
                    // its lit tone and its colour a little stronger, as the eye takes it.
                    let centre = Polygon.mean(p), rr = length(p[0] - centre)
                    let cc = centre - SIMD2(Double(x0), Double(y0))
                    var ring: [SIMD3<Float>] = []
                    for (j, q) in at.enumerated() {
                        let d = length(SIMD2(Double(q.x), Double(q.y)) - cc)
                        if d > 0.4 * rr && d < 0.85 * rr { ring.append(px[j]) }
                    }
                    if ring.count <= 10 { ring = px }
                    c = OKLab.from(Stats.median(brightest(ring, 70, above: true)))
                    c = SIMD3(c.x, c.y * 1.4, c.z * 1.4)
                }
                if t.eye == .pupil { c = OKLab.from(Stats.percentile(px, 5)) }
                if t.feature == "eye" {
                    // An eye's white: the lit part of the stones under the tile.
                    c = OKLab.from(Stats.median(brightest(px, 60, above: true)))
                }
                if t.feature == "mid" {
                    // The feature's own shadow: the darker part of the stones under it.
                    c = OKLab.from(Stats.median(brightest(px, 35, above: false)))
                    c = SIMD3(c.x * 0.86, c.y * 1.15, c.z * 1.15)
                }
                if t.strand { c = SIMD3(Swift.min(c.x, 0.30), c.y * 0.8, c.z * 0.8) }
                med.append(c)
            }
            // Shade in zones, as a mosaicist grades it: a field tile's colour leans on its neighbours'.
            let centres = pieces.map { Polygon.mean($0.poly) }
            let field = pieces.indices.filter { pieces[$0].strand == false && pieces[$0].eye == nil && pieces[$0].feature == nil }
            let reach = 1.7 * Swift.max(s, fine)
            let cols = Swift.max(Int((Double(W) / reach).rounded(.up)), 1), rowsN = Swift.max(Int((Double(H) / reach).rounded(.up)), 1)
            var buckets = [[Int]](repeating: [], count: cols * rowsN)
            func cell(_ c: SIMD2<Double>) -> (Int, Int) {
                (clampIndex(Int((c.x / reach).rounded(.down)), cols), clampIndex(Int((c.y / reach).rounded(.down)), rowsN))
            }
            for i in field { let (cx, cy) = cell(centres[i]); buckets[cy * cols + cx].append(i) }
            var calm = med
            for i in field {
                let r = 1.7 * layout.pitch(centres[i]), (cx, cy) = cell(centres[i])
                var near: [SIMD3<Float>] = []
                for yy in Swift.max(cy - 1, 0)...Swift.min(cy + 1, rowsN - 1) {
                    for xx in Swift.max(cx - 1, 0)...Swift.min(cx + 1, cols - 1) {
                        for j in buckets[yy * cols + xx] where length(centres[j] - centres[i]) <= r { near.append(med[j]) }
                    }
                }
                calm[i] = 0.4 * med[i] + 0.6 * Stats.median(near)
            }
            return calm
        }

        /// The paints: k-means of the tiles' colours (the face's fine tiles counted thrice, the
        /// features' five times), each paint its members' median; an eye keeps its own glass.
        func palette(_ med: [SIMD3<Float>]) -> Mosaic {
            let pieces = layout.pieces
            let weight = SIMD3<Float>(1, 1.5, 1.5)
            let Xc = med.map { $0 * weight }
            let centres = pieces.map { Polygon.mean($0.poly) }
            let fineTile = centres.map { layout.pitch($0) < s * 0.8 }
            let feat = pieces.map { $0.feature != nil }
            var Xw = Xc
            for _ in 0..<2 { Xw += Xc.indices.filter { fineTile[$0] }.map { Xc[$0] } }
            for _ in 0..<4 { Xw += Xc.indices.filter { feat[$0] }.map { Xc[$0] } }
            var rng = SplitMix64(seed: 18)
            let km = KMeans.run(Xw, k: paints, maxIterations: 200, epsilon: 1e-5, attempts: 10, rng: &rng)
            if let path = getenv("MOSAIC_DUMP_XW") {   // DEBUG-DUMP
                let f = fopen(String(cString: path), "w")!   // DEBUG-DUMP
                fputs("\(km.compactness)\n", f)   // DEBUG-DUMP
                for v in Xw { fputs("\(v.x) \(v.y) \(v.z)\n", f) }   // DEBUG-DUMP
                fclose(f)   // DEBUG-DUMP
            }   // DEBUG-DUMP
            let a = Xc.map { KMeans.nearest($0, km.centers) }
            var palette: [SIMD3<Float>] = []
            var remap = [Int](repeating: -1, count: km.centers.count)
            for j in km.centers.indices {
                let members = a.indices.filter { a[$0] == j }
                guard !members.isEmpty else { continue }
                remap[j] = palette.count
                palette.append(OKLab.toRGB(Stats.median(members.map { med[$0] })))
            }
            var paint = a.map { remap[$0] }
            // An eye keeps its own glass (iris and pupil): its own paint unless one is already as
            // near as can be seen.
            for (i, t) in pieces.enumerated() where t.eye != nil {
                var best = -1, bd = Float.infinity
                for (j, c) in palette.enumerated() {
                    let d = length(OKLab.from(c) - med[i])
                    if d < bd { bd = d; best = j }
                }
                if best >= 0 && bd < 0.015 {
                    paint[i] = best
                } else {
                    paint[i] = palette.count; palette.append(OKLab.toRGB(med[i]))
                }
            }
            let grout = OKLab.toRGB(SIMD3(0.86, 0.004, 0.012))
            let half = 1 / Double(Self.scale)
            let tiles = pieces.enumerated().map { i, t in
                let corners = t.poly.map { SIMD2<Float>(Float($0.x * half), Float($0.y * half)) }
                let c = corners.reduce(SIMD2<Float>(0, 0), +) / Float(corners.count)
                let stone = boxes.contains { b in c.x >= b[0] && c.x <= b[2] && c.y >= b[1] && c.y <= b[3] }
                return Mosaic.Tile(corners: corners, paint: paint[i], stone: stone)
            }
            return Mosaic(width: Float(w0), height: Float(h0), grout: grout, palette: palette, tiles: tiles)
        }

        @inline(__always) func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
        @inline(__always) func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
    }
}
