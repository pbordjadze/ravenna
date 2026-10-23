#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The making-of show: a mosaic set the way the old workshops set one, step by step, each step's
/// technique named on a card (`MakingOf.Card`; the words and their sources: docs/making-of.md).
///
/// `MakingOf.Show` is its plan, a pure function of the mosaic, the options and the time, so a view
/// can seek it and hold it still: what scene is playing, which card shows and how strongly, where
/// each tile is (waiting, dropping in, set), how much of the drawing and the painted bed are laid,
/// how each tile flares under the closing light, and each smalti's cake. A tile is never painted on:
/// it drops in from above, a little large, its shadow under it, and settles, catching a warm light
/// as it lands.
///
/// `prototype/making_of_plan.py` is the reference, and this its port line by line, in Double;
/// `prototype/making_of.py` draws it. `Tests/MosaicKitTests/MakingOfTests.swift` checks the two
/// agree on a fixture the reference writes (its doc comment says how).
nonisolated public enum MakingOf {
    /// The scenes, in the order they play, and their lengths in seconds.
    nonisolated public enum Scene: String, CaseIterable, Sendable, Codable {
        /// The picture the mosaic is made from.
        case model
        /// The glass: each paint a cake, cooling, then cut into tesserae.
        case smalti
        /// The drawing on the bed, stroke by stroke.
        case sinopia
        /// The painted setting bed spreading over the drawing.
        case bed
        /// The face first: its features, its eyes, then its fine stone.
        case face
        /// The strands.
        case outlines
        /// The rows that echo them, and the field.
        case andamento
        /// The finished mosaic under a moving light.
        case light
        /// The finished mosaic, held, with the closing card.
        case hold

        public var length: Double {
            switch self {
            case .model: 3.0
            case .smalti: 5.5
            case .sinopia: 5.0
            case .bed: 3.5
            case .face: 6.5
            case .outlines: 5.0
            case .andamento: 9.0
            case .light: 5.5
            case .hold: 5.0
            }
        }

        /// The scenes in which tiles are set.
        public static let build: [Scene] = [.face, .outlines, .andamento]
    }

    /// Seconds a tile takes to drop and settle.
    public static let setTime = 0.42
    /// A card's fade in and out, in seconds.
    public static let fade = 0.5

    /// A tile in flight: its lift above its place and its scale (0 and 1 when it lands), in canvas
    /// units; the strength of its shadow under it; the warm light it catches as it lands.
    nonisolated public struct Flight: Sendable, Equatable {
        public var lift: Double
        public var scale: Double
        public var shadow: Double
        public var glow: Double
    }

    nonisolated public enum TileState: Sendable, Equatable {
        case waiting
        case flying(Flight)
        case set
    }

    /// A smalti's cake in the smalti scene: how far it has appeared, cooled from glowing orange to
    /// its colour, and been cut into tesserae, each 0...1.
    nonisolated public struct Cake: Sendable, Equatable {
        public var shown: Double
        public var cool: Double
        public var cut: Double
    }

    public static func ease(_ u: Double) -> Double {
        let u = min(max(u, 0), 1)
        return u * u * (3 - 2 * u)
    }

    public static func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Gold smalti, as `TileColor.isGold` finds it, in Double (the reference's arithmetic).
    static func isGold(_ rgb: SIMD3<Double>) -> Bool {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(rgb.x), g = lin(rgb.y), b = lin(rgb.z)
        let l = pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3)
        let m = pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3)
        let s = pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let hue = atan2(B, A) * 180 / Double.pi
        return L > 0.55 && (A * A + B * B).squareRoot() > 0.07 && hue > 55 && hue < 105
    }

    nonisolated public struct Show: Sendable {
        public let options: Options
        /// Each scene's start and length in seconds (the face and the outlines last 0 when the mosaic
        /// has none).
        public let times: [Scene: (start: Double, length: Double)]
        public let duration: Double
        /// The side of the median tile, in canvas units.
        public let pitch: Double
        /// Each tile's scene: the face (its features, eyes and stone), the outlines (strands) or the
        /// andamento (rows, the field, and every tile of a mosaic without stages).
        public let sceneOf: [Scene]
        /// When each tile starts to drop.
        public let start: [Double]
        /// The drawing: strokes through the strands' and features' tiles, nearest the face first, and
        /// the part of the whole drawing's length each covers.
        public let strokes: [[SIMD2<Double>]]
        public let strokeSpans: [(from: Double, to: Double)]
        /// The paints in the order their cakes appear: the most used first.
        public let cakeOrder: [Int]
        let centres: [SIMD2<Double>]
        let stone: [Bool]
        let gold: [Bool]
        let sweep: [Double]
        let tilt: [SIMD2<Double>]
        let cards: [(scene: Scene, from: Double, to: Double)]

        public init(_ mosaic: Mosaic, options: Options = Options()) {
            self.options = options
            let n = mosaic.tiles.count
            let width = Double(mosaic.width), height = Double(mosaic.height)
            var centres: [SIMD2<Double>] = [], areas: [Double] = []
            for t in mosaic.tiles {
                let c = t.corners.map { SIMD2(Double($0.x), Double($0.y)) }
                var x = 0.0, y = 0.0
                for p in c { x += p.x; y += p.y }
                centres.append(SIMD2(x / Double(c.count), y / Double(c.count)))
                var a = 0.0
                for k in c.indices {
                    let q = c[(k + 1) % c.count]
                    a += c[k].x * q.y - q.x * c[k].y
                }
                areas.append(abs(a) / 2)
            }
            areas.sort()
            pitch = areas.isEmpty ? 1 : areas[areas.count / 2].squareRoot()
            self.centres = centres
            stone = mosaic.tiles.map(\.stone)
            let stage = mosaic.tiles.map(\.stage)
            var sceneOf: [Scene] = [], rank: [Int] = []
            for i in 0..<n {
                let g = stage[i]
                if g == .feature || g == .eye || stone[i] { sceneOf.append(.face) }
                else if g == .strand { sceneOf.append(.outlines) }
                else { sceneOf.append(.andamento) }
                rank.append(g == .feature ? 0 : g == .eye ? 1 : 2)
            }
            self.sceneOf = sceneOf
            var times: [Scene: (start: Double, length: Double)] = [:]
            var t = 0.0
            for s in Scene.allCases {
                let empty = (s == .face || s == .outlines) && !sceneOf.contains(s)
                let d = empty ? 0 : s.length
                times[s] = (t, d); t += d
            }
            self.times = times
            duration = t
            var order: [Scene: [Int]] = [:]
            for k in Scene.build {
                order[k] = (0..<n).filter { sceneOf[$0] == k }.sorted { (rank[$0], $0) < (rank[$1], $1) }
            }
            var start = [Double](repeating: .infinity, count: n)
            switch options.flow {
            case .scenes:
                for k in Scene.build {
                    let (s, d) = times[k]!, idx = order[k]!
                    for (j, i) in idx.enumerated() {
                        var u = idx.count > 1 ? Double(j) / Double(idx.count - 1) : 0
                        // Slow to begin, as the first rows are found, then quicker as the setters fill in.
                        u = pow(u, k == .andamento ? 0.65 : 0.8)
                        start[i] = s + 0.15 * d + u * (0.72 * d - MakingOf.setTime)
                    }
                }
            case .continuous:
                let s = times[Scene.build[0]]!.start
                var d = 0.0
                for k in Scene.build { d += times[k]!.length }
                let idx = Scene.build.flatMap { order[$0]! }
                for (j, i) in idx.enumerated() {
                    let u = pow(idx.count > 1 ? Double(j) / Double(idx.count - 1) : 0, 0.7)
                    start[i] = s + 0.06 * d + u * (0.88 * d - MakingOf.setTime)
                }
            }
            self.start = start
            // The cards: one a scene, or in the continuous build one a stage, from its first tile to the next's.
            var cards: [(scene: Scene, from: Double, to: Double)] = []
            for s in Scene.allCases {
                let (a, d) = times[s]!
                if d == 0 || (options.flow == .continuous && Scene.build.contains(s)) { continue }
                cards.append((s, a, a + d))
            }
            if options.flow == .continuous {
                let firsts = Scene.build.compactMap { k in order[k]!.first.map { (k, start[$0]) } }
                let end = times[.light]!.start
                for (j, (k, a)) in firsts.enumerated() {
                    let b = j + 1 < firsts.count ? firsts[j + 1].1 : end
                    cards.append((k, j > 0 ? a - 0.3 : times[Scene.build[0]]!.start, b))
                }
                cards = cards.enumerated().sorted { ($0.element.from, $0.offset) < ($1.element.from, $1.offset) }.map(\.element)
            }
            self.cards = cards
            // The drawing: the strands' and features' tiles chained into strokes, nearest the face first.
            var fc = SIMD2(width / 2, height / 2)
            let face = (0..<n).filter { sceneOf[$0] == .face }
            if !face.isEmpty {
                var x = 0.0, y = 0.0
                for i in face { x += centres[i].x; y += centres[i].y }
                fc = SIMD2(x / Double(face.count), y / Double(face.count))
            }
            var chains: [[Int]] = [], cur: [Int] = []
            for i in 0..<n where stage[i] == .strand || stage[i] == .feature {
                if let last = cur.last, stage[last] != stage[i] || MakingOf.distance(centres[last], centres[i]) > 1.6 * pitch {
                    chains.append(cur); cur = []
                }
                cur.append(i)
            }
            if !cur.isEmpty { chains.append(cur) }
            let lines = chains.filter { $0.count >= 2 }.map { $0.map { centres[$0] } }
            func far(_ s: [SIMD2<Double>]) -> Double {
                var d = 0.0
                for q in s { d += MakingOf.distance(q, fc) }
                return d / Double(s.count)
            }
            strokes = lines.enumerated().map { (far($0.element), $0.offset) }.sorted { $0 < $1 }.map { lines[$0.1] }
            var lengths: [Double] = []
            for s in strokes {
                var L = 0.0
                for k in 1..<s.count { L += MakingOf.distance(s[k - 1], s[k]) }
                lengths.append(L)
            }
            var total = 0.0
            for L in lengths { total += L }
            if total == 0 { total = 1 }
            var acc = 0.0, spans: [(from: Double, to: Double)] = []
            for L in lengths { spans.append((acc / total, (acc + L) / total)); acc += L }
            strokeSpans = spans
            // The light: where each tile is along its sweep, and each tile's tilt.
            sweep = centres.map { $0.x / width * 0.55 + $0.y / height * 0.45 }
            let palette = mosaic.palette.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) }
            let goldPaint = palette.map(MakingOf.isGold)
            gold = mosaic.tiles.map { goldPaint[$0.paint] }
            tilt = (0..<n).map { [stone, gold] i in
                let k = (stone[i] ? 0.25 : 1.0) * (gold[i] ? 1.6 : 1.0)
                return SIMD2(Double(TileColor.wobble(i, salt: 4)) * k, Double(TileColor.wobble(i, salt: 5)) * k)
            }
            let counts = mosaic.tilesPerPaint
            cakeOrder = palette.indices.sorted { (-counts[$0], $0) < (-counts[$1], $1) }
        }

        /// The scene playing at `t`, and how far through it (0...1).
        public func scene(at t: Double) -> (scene: Scene, progress: Double) {
            for s in Scene.allCases {
                let (a, d) = times[s]!
                if d > 0, t < a + d { return (s, (t - a) / d) }
            }
            return (.hold, 1)
        }

        /// The card showing at `t` and its opacity, if one is. Two never show at once; the closing
        /// card stays.
        public func card(at t: Double) -> (scene: Scene, opacity: Double)? {
            for c in cards where (c.from <= t && t < c.to) || (c.scene == .hold && t >= c.from) {
                let fadeOut = c.scene == .hold ? 1 : MakingOf.ease((c.to - t) / MakingOf.fade)
                return (c.scene, MakingOf.ease((t - c.from) / MakingOf.fade) * fadeOut)
            }
            return nil
        }

        public func tile(_ i: Int, at t: Double) -> TileState {
            let s = start[i]
            if t < s { return .waiting }
            if t >= s + MakingOf.setTime { return .set }
            let u = (t - s) / MakingOf.setTime
            let e = 1 - pow(1 - u, 3)
            return .flying(Flight(
                lift: (1 - e) * 0.9 * pitch, scale: 1 + 0.45 * (1 - e), shadow: 0.15 + 0.3 * (1 - e),
                glow: exp(-pow((u - 0.82) / 0.12, 2)) * (stone[i] ? 0.35 : 0.6)))
        }

        /// The setter's hand, when the options show it: over the tile most recently begun, while one
        /// is in flight.
        public func hand(at t: Double) -> SIMD2<Double>? {
            guard options.hand else { return nil }
            var best: Int?
            for (i, s) in start.enumerated() where s <= t && t < s + MakingOf.setTime {
                if best == nil || s > start[best!] { best = i }
            }
            guard let i = best, case .flying(let f) = tile(i, at: t) else { return nil }
            return SIMD2(centres[i].x, centres[i].y - f.lift)
        }

        /// How much of the drawing is drawn at `t`, 0...1 of its whole length.
        public func sinopia(at t: Double) -> Double {
            let (s, d) = times[.sinopia]!
            return min(max((t - s - 0.4) / (d - 1.0), 0), 1)
        }

        /// The painted bed's front at `t`, down the picture as a fraction of its height: 0 none, past 1
        /// all (its edge soft over 0.08).
        public func bed(at t: Double) -> Double {
            let (s, d) = times[.bed]!
            return (t - s - 0.2) / (d - 0.6) * 1.15
        }

        /// How much tile `i` flares at `t` under the light crossing the finished mosaic: gold most,
        /// glass less, stone least, each at its own tilt.
        public func light(_ i: Int, at t: Double) -> Double {
            let (s, d) = times[.light]!
            let u = min(max((t - s) / d, 0), 1)
            let x = -0.25 + 1.5 * MakingOf.ease(u)
            let a = SIMD2(cos(2.4 * u), sin(2.4 * u))
            let facing = min(max(0.4 + 0.9 * (tilt[i].x * a.x + tilt[i].y * a.y), 0), 1)
            let meet = exp(-pow((sweep[i] - x) / 0.13, 2)) * facing
            return meet * (stone[i] ? 0.25 : 0.7) * (gold[i] ? 1.8 : 1.0)
        }

        /// Paint `p`'s cake at the smalti scene's progress `u`.
        public func cake(_ p: Int, at u: Double) -> Cake {
            let n = cakeOrder.count
            let r = Double(cakeOrder.firstIndex(of: p) ?? 0) / Double(max(n - 1, 1))
            let appear = 0.05 + 0.4 * r
            return Cake(shown: MakingOf.ease((u - appear) / 0.08), cool: MakingOf.ease((u - appear) / 0.22),
                        cut: MakingOf.ease((u - 0.62 - 0.15 * r) / 0.12))
        }
    }
}
