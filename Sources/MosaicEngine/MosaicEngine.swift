#if canImport(MosaicKit)
import MosaicKit
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
        /// The same in a face: CUT_FINE, raised from the script's 0.45 since the features come from
        /// landmarks (sketchbook round 6): lower, an old face's wrinkles became dark rows across it.
        public var faceCut: Float = 0.6
        /// The joint between tiles, in working pixels: GROUT (the tight set).
        public var grout: Int = 2
        /// How an iris is coloured (issue #9, an option until Paul narrows it).
        public var eyes: Eyes = .asTheyLook
        /// How a mouth is set (issue #1, an option until Paul narrows it).
        public var mouth: Mouth = .asInThePhoto
        public init() {}
    }

    /// An iris's colour: as the eye takes it beside the face (its lit tone, a little stronger: the
    /// prototype's way, which gave the cat gold eyes) or as the photo has it (the ring's median:
    /// the cat's olive-brown).
    nonisolated public enum Eyes: String, Sendable, Equatable, CaseIterable {
        case asTheyLook, asInThePhoto
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

    /// One face's features in the photo's pixels, as `sketchbook/features.py` writes them. Several
    /// faces are laid as one: their boxes, eyes and lines together.
    nonisolated public struct Face: Sendable, Codable, Equatable {
        /// x0, y0, x1, y1: where the tiles are finer, the outline cut lower and the tiles stone.
        public var box: [Float]
        /// Each [cx, cy, iris r, pupil r]: the iris one round piece, cut by the eye's opening, the
        /// pupil laid over it. A fifth value, when given, is the pupil's height (a cat's slit); a
        /// third alone means no pupil.
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
    /// no face boxes, no fine pitch, no eyes). `cancel` is polled between stages (throwing
    /// `CancellationError`).
    ///
    /// The mosaic's tiles come in the order they were laid, each with its `stage`: the eyes' irises
    /// and the features' rows first, then the strands, the rows, the field, and last the pupils (each
    /// laid over its iris, as the script does). The making-of replays the build from that order.
    /// Corners are in the photo's pixels; a tile is stone when its centre is in a face's box.
    /// `progress` hears how much of the work is done (0...1) after each stage, for a progress bar.
    public static func make(photo: Photo, contours: [Float], faces: [Face], settings: Settings = Settings(),
                            cancel: () -> Bool = { false }, progress: (Double) -> Void = { _ in }) throws -> Mosaic {
        var trace = Trace()
        return try make(photo: photo, contours: contours, faces: faces, settings: settings, cancel: cancel,
                        progress: progress, trace: &trace)
    }

    /// Each stage's share of the work, by its time on a 1448 px portrait (`mosaic` on Linux): what
    /// `progress` adds up after it.
    static let shares: [String: Double] = [
        "upscale": 0.07, "strokes": 0.05, "strands": 0.01, "segments": 0.23, "distance": 0.07,
        "rows": 0.08, "gaps": 0.28, "colours": 0.14, "palette": 0.07,
    ]

    /// `make`, recording in `trace` each stage's time and tiles, and which tiles are strands and features.
    public static func make(photo: Photo, contours: [Float], faces: [Face], settings: Settings = Settings(),
                            cancel: () -> Bool, progress: (Double) -> Void = { _ in }, trace: inout Trace) throws -> Mosaic {
        guard photo.width > 0, photo.height > 0, photo.rgb.count == photo.width * photo.height else {
            throw InputError.photoSize
        }
        guard contours.count == photo.width * photo.height else { throw InputError.contourSize }
        var photo = photo, contours = contours, faces = faces
        if settings.mouth == .byzantine { byzantineMouths(&photo, &contours, &faces) }
        let run = Run(photo: photo, contours: contours, faces: faces, settings: settings)
        return try run.make(cancel: cancel, progress: progress, trace: &trace)
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
        let irises: Eyes
        let photo: Photo, contours: [Float]
        /// The photo at the working size, by channel, and the drawing.
        var red: [Float] = [], green: [Float] = [], blue: [Float] = []
        var draw: [Float] = []
        var pitchMap: Plane
        var layout: Layout

        init(photo: Photo, contours: [Float], faces: [Face], settings: Settings) {
            g = Swift.max(settings.grout, 0)
            s = Swift.max(Double(settings.pitch), Double(g) + 2)
            let faces = faces.map(Run.inProfile)
            // A small face gets smaller pieces, as mosaicists kept their smallest for faces: at least
            // 24 across its box (a face under about 200 px of the photo), but never under 8 px.
            let across = faces.filter { $0.box.count >= 4 }.map { Double($0.box[2] - $0.box[0]) * Double(Self.scale) / 24 }.min()
            fine = Swift.max(Swift.min(Double(settings.facePitch), across ?? .infinity),
                             Swift.min(Double(settings.facePitch), 8), Double(g) + 2)
            paints = Swift.max(settings.paints, 1)
            cut = settings.cut; faceCut = settings.faceCut
            irises = settings.eyes
            w0 = photo.width; h0 = photo.height
            W = w0 * Self.scale; H = h0 * Self.scale
            boxes = faces.map(\.box).filter { $0.count >= 4 }
            eyes = faces.flatMap(\.eyes).filter { $0.count >= 3 }
            lines = faces.flatMap(\.lines)
            eyeRings = lines.filter { $0.kind == "eye" }.map { Run.points($0.pts) }
            self.photo = photo; self.contours = contours
            pitchMap = Plane(width: W, height: H, value: Float(s))
            layout = Layout(width: W, height: H, grout: g, pitchMap: [])
        }

        /// A face in profile without the eye it hides: when its eyes are closer together than a
        /// fifth of its box's width (a turned head's are a third or more; Duckworth's profile in
        /// Cameron's print, 0.17), the far one, the eye nearer the box's edge, is behind the nose,
        /// and the landmarks only guess it. It goes, with its lids and opening and the brow above it.
        static func inProfile(_ face: Face) -> Face {
            guard face.box.count >= 4, face.eyes.count == 2, face.eyes.allSatisfy({ $0.count >= 3 }) else { return face }
            let a = face.eyes[0], b = face.eyes[1]
            let width = face.box[2] - face.box[0], mid = (face.box[0] + face.box[2]) / 2
            let apart = ((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1])).squareRoot()
            guard width > 0, apart < 0.2 * width else { return face }
            let far = abs(a[0] - mid) > abs(b[0] - mid) ? a : b
            let reach = Swift.max(apart, 4 * far[2])
            func centre(_ l: Face.Line) -> SIMD2<Float> {
                let p = l.pts.filter { $0.count >= 2 }
                return p.isEmpty ? SIMD2<Float>(.infinity, .infinity) : p.reduce(SIMD2<Float>.zero) { $0 + SIMD2($1[0], $1[1]) } / Float(p.count)
            }
            var out = face
            out.eyes = face.eyes.filter { $0 != far }
            out.lines = face.lines.filter { l in
                let c = centre(l), dx = abs(c.x - far[0]), dy = c.y - far[1]
                switch l.kind {
                case "eye", "dark", "tone": return (dx * dx + dy * dy).squareRoot() >= 3 * far[2]
                case "mid": return !(dx < reach && dy < 0 && dy > -reach)
                default: return true
                }
            }
            return out
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

        func make(cancel: () -> Bool, progress: (Double) -> Void, trace: inout Trace) throws -> Mosaic {
            let clock = ContinuousClock()
            var last = clock.now
            var done = 0.0
            func lap(_ name: String) throws {
                done += MosaicEngine.shares[name] ?? 0
                progress(Swift.min(done, 1))
                let now = clock.now, d = now - last
                trace.stages.append(.init(name: name, seconds: Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18,
                                          tiles: layout.pieces.count))
                last = now
                if cancel() { throw CancellationError() }
            }
            // The photo at twice its size (bicubic), the drawing with it (bilinear).
            func channel(_ c: Int) -> [Float] {
                Resize.upscale2x(photo.rgb.map { $0[c] }, width: w0, height: h0).map { Swift.min(Swift.max($0, 0), 1) }
            }
            red = channel(0); green = channel(1); blue = channel(2)
            draw = Resize.bilinear(contours, width: w0, height: h0, to: W, H)
            // The pitch: finer in the faces.
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
                lay(row: P, stage: .strand, strand: true, minFrac: 0.35, feature: nil)
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
            let linked = Strokes.link(Strokes.chains(skeleton, width: W, height: H), reach: s * 0.9)
            var guides: [[SIMD2<Double>]] = []
            for P in linked where Double(P.count) >= 2.2 * s {
                guides.append(Blur.smooth(P, sigma: s * 0.35, wrap: false))
            }
            // Longest first; the sort keeps the order of equals.
            return guides.indices.sorted { guides[$0].count != guides[$1].count ? guides[$0].count > guides[$1].count : $0 < $1 }
                .map { guides[$0] }
        }

        /// A row of square tiles along a polyline.
        func lay(row P: [SIMD2<Double>], stage: Mosaic.Stage, strand: Bool, minFrac: Double, feature: String?) {
            let (pts, _) = layout.resample(P)
            for (i, p) in pts.enumerated() {
                var a = pts[Swift.max(i - 1, 0)], b = pts[Swift.min(i + 1, pts.count - 1)]
                if pts.count == 1 { a = P[0]; b = P[P.count - 1] }
                layout.place(layout.square(p, b - a), stage: stage, strand: strand, minFrac: minFrac, feature: feature)
            }
        }

        /// The part of an iris or pupil inside its eye's opening (all of it when there is none). With
        /// `inset`, inside the opening drawn that much closer round the piece's centre: a pupil
        /// keeps clear of the lid that cuts its iris, so the two never share an outline (a template
        /// needs grout between them, `MosaicCore.template`); nil when the centre is that near the lid.
        func lidded(_ poly: [SIMD2<Double>], inset: Double = 0) -> [SIMD2<Double>]? {
            let c = Polygon.mean(poly)
            for ring in eyeRings where Polygon.contains(ring, c) {
                guard inset > 0 else { return intersect(poly, ring) ?? poly }
                let near = zip(ring, ring.dropFirst() + ring.prefix(1)).map { Polygon.segmentDistance(c, $0, $1) }.min() ?? 0
                guard near > inset else { return nil }
                let f = 1 - inset / near
                return intersect(poly, ring.map { c + ($0 - c) * f })
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
                        let (sin, cos) = Exact.sinCos(2 * Double.pi * Double(i) / 28)
                        return c + SIMD2(rx * cos, ry * sin)
                    }
                }
                layout.place(lidded(ring(rr, rr))!, stage: .eye, strand: false, minFrac: 0.1, eye: .iris)
                if e.count > 3 {
                    let px = Double(e[3]) * k, py = Double(e.count > 4 ? e[4] : e[3]) * k
                    if let pupil = lidded(ring(px, py), inset: 1.5) {
                        pupils.append(Layout.Piece(poly: pupil, strand: false, eye: .pupil, feature: nil, stage: .eye))
                    }
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
                lay(row: P, stage: .feature, strand: ln.kind == "dark", minFrac: 0.3, feature: ln.kind)
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
                        layout.place(layout.square(pts[i], pts[(i + 1) % n] - pts[(i + n - 1) % n]), stage: .row,
                                     strand: false, minFrac: 0.25)
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
                    if layout.place(layout.square(SIMD2(Double(x), Double(y)), t, grow: 1.12), stage: .field, strand: false,
                                    minFrac: 0.3) {
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
            // A toned photo's cast (a sepia print's warmth): an iris is made stronger away from it, so
            // its eyes don't turn orange. The cast is the median colour of every 7th pixel, in OKLab;
            // it counts when nine pixels in ten lie within 0.04 of it (Cameron's prints: 0.02 to
            // 0.036), fading out by 0.06, since a colour photo's median is its subject (a face's
            // warmth, from 0.054 up in the Kodak portraits), not a cast.
            var cast = SIMD3<Float>.zero
            if irises == .asTheyLook && !eyes.isEmpty {
                let sample = stride(from: 0, to: W * H, by: 7).map { Colour.lab(SIMD3(red[$0], green[$0], blue[$0])) }
                let median = Stats.median(sample)
                var spread = sample.map { ((SIMD2($0.y, $0.z) - SIMD2(median.y, median.z)) * (SIMD2($0.y, $0.z) - SIMD2(median.y, median.z))).sum().squareRoot() }
                let toned = Swift.min(Swift.max((0.06 - Stats.percentile(&spread, 90)) / 0.02, 0), 1)
                cast = SIMD3(0, median.y * toned, median.z * toned)
            }
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
                var c = Colour.lab(Stats.median(px))
                if t.eye == .iris {
                    // The iris's own glass: its ring, outside the pupil and inside the lids' shadow,
                    // its lit tone and its colour a little stronger, as the eye takes it. The ring is
                    // measured from the eye's own centre and radius: the piece is cut by the lids,
                    // so its own middle and corners would put the ring on the lids and the white.
                    let mean = Polygon.mean(p)
                    let eye = eyes.min { length(SIMD2(Double($0[0]), Double($0[1])) * Double(Self.scale) - mean)
                        < length(SIMD2(Double($1[0]), Double($1[1])) * Double(Self.scale) - mean) }
                    let centre = eye.map { SIMD2(Double($0[0]), Double($0[1])) * Double(Self.scale) } ?? mean
                    let rr = eye.map { Double($0[2]) * Double(Self.scale) } ?? length(p[0] - mean)
                    // From the photo's own pixels, not the working image: the upscale's overshoot at
                    // an iris's edges (a few pixels across) would tint the ring.
                    let k = Double(Self.scale)
                    var ring: [SIMD3<Float>] = []
                    let cx = centre.x / k, cy = centre.y / k, r0 = rr / k
                    let ys = Swift.max(Int((cy - r0).rounded(.down)), 0)...Swift.min(Int((cy + r0).rounded(.up)), h0 - 1)
                    let xs = Swift.max(Int((cx - r0).rounded(.down)), 0)...Swift.min(Int((cx + r0).rounded(.up)), w0 - 1)
                    if !ys.isEmpty && !xs.isEmpty {
                        for y in ys {
                            for x in xs {
                                let q = SIMD2(Double(x) + 0.5, Double(y) + 0.5), d = length(q - SIMD2(cx, cy))
                                if d > 0.5 * r0 && d < 0.85 * r0 && Polygon.contains(p, q * k) { ring.append(photo.rgb[y * w0 + x]) }
                            }
                        }
                    }
                    if ring.count < 4 { ring = px }
                    switch irises {
                    case .asTheyLook:
                        // Its lit tone, but no more than a little above its own: an iris in a shadowed
                        // socket doesn't glow.
                        let lit = Colour.lab(Stats.median(brightest(ring, 70, above: true)))
                        let own = Colour.lab(Stats.median(ring))
                        c = SIMD3(Swift.min(lit.x, own.x + 0.06),
                                  cast.y + (lit.y - cast.y) * 1.4, cast.z + (lit.z - cast.z) * 1.4)
                    case .asInThePhoto:
                        c = Colour.lab(Stats.median(ring))
                    }
                }
                if t.eye == .pupil { c = Colour.lab(Stats.percentile(px, 5)) }
                if t.feature == "eye" {
                    // An eye's white: the lit part of the stones under the tile.
                    c = Colour.lab(Stats.median(brightest(px, 60, above: true)))
                }
                if t.feature == "mid" {
                    // The feature's own shadow: the darker part of the stones under it.
                    c = Colour.lab(Stats.median(brightest(px, 35, above: false)))
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
            let a = Xc.map { KMeans.nearest($0, km.centers) }
            var palette: [SIMD3<Float>] = []
            var remap = [Int](repeating: -1, count: km.centers.count)
            for j in km.centers.indices {
                let members = a.indices.filter { a[$0] == j }
                guard !members.isEmpty else { continue }
                remap[j] = palette.count
                palette.append(Colour.rgb(Stats.median(members.map { med[$0] })))
            }
            var paint = a.map { remap[$0] }
            // A face's tiles take the paint nearest in colour as well as tone: a pale cheek otherwise
            // joins whatever cluster is nearest in lightness, and on the astronaut that was her
            // suit's grey, a grey tile in the skin (sketchbook round 6).
            let inFace = boxes.isEmpty ? [Bool](repeating: false, count: pieces.count) : centres.map { c in
                boxes.contains { b in c.x >= Double(b[0]) * Double(Self.scale) && c.x <= Double(b[2]) * Double(Self.scale)
                    && c.y >= Double(b[1]) * Double(Self.scale) && c.y <= Double(b[3]) * Double(Self.scale) } }
            let skin = SIMD3<Float>(1, 2.5, 2.5), labs = palette.map { Colour.lab($0) * skin }
            for i in pieces.indices where inFace[i] && pieces[i].eye == nil {
                let x = med[i] * skin
                var best = paint[i], bd = Float.infinity
                for (j, c) in labs.enumerated() {
                    let d = ((c - x) * (c - x)).sum()
                    if d < bd { bd = d; best = j }
                }
                paint[i] = best
            }
            // An eye keeps its own glass (iris and pupil): its own paint unless one is already as
            // near as can be seen.
            for (i, t) in pieces.enumerated() where t.eye != nil {
                var best = -1, bd = Float.infinity
                for (j, c) in palette.enumerated() {
                    let d = length(Colour.lab(c) - med[i])
                    if d < bd { bd = d; best = j }
                }
                if best >= 0 && bd < 0.015 {
                    paint[i] = best
                } else {
                    paint[i] = palette.count; palette.append(Colour.rgb(med[i]))
                }
            }
            let grout = Colour.rgb(SIMD3(0.86, 0.004, 0.012))
            let half = 1 / Double(Self.scale)
            let tiles = pieces.enumerated().map { i, t in
                let corners = t.poly.map { SIMD2<Float>(Float($0.x * half), Float($0.y * half)) }
                let c = corners.reduce(SIMD2<Float>(0, 0), +) / Float(corners.count)
                let stone = boxes.contains { b in c.x >= b[0] && c.x <= b[2] && c.y >= b[1] && c.y <= b[3] }
                return Mosaic.Tile(corners: corners, paint: paint[i], stone: stone, stage: t.stage)
            }
            return Mosaic(width: Float(w0), height: Float(h0), grout: grout, palette: palette, tiles: tiles)
        }

        @inline(__always) func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
        @inline(__always) func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
    }
}
