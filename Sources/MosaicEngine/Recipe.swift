#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(MosaicKit)
import MosaicKit
#endif

nonisolated extension MosaicEngine {
    /// What a mosaic is made with, as the painter chose it in the create flow: how many pieces, how
    /// the eyes and the mouth are set, the ground and the panel of the photo laid, and what they drew
    /// on it in Refine (`marks`). Each is a creative fork kept as an option until Paul narrows it.
    /// (The finish is how any mosaic is shown, the
    /// app's setting, as in v0: it changes no tile or paint. The gold ground gives the background a
    /// paint of its own, so it is the mosaic's.) The app records it with the
    /// artwork (`meta.json`'s `recipe`), so a mosaic is made again as it was made.
    ///
    /// Decoding is tolerant: a field missing or unknown (written by an older or a newer app) takes
    /// its default, so a recipe never fails a painting. Never rename a field.
    nonisolated public struct Recipe: Sendable, Equatable, Hashable, Codable {
        /// The Pieces slider, 0...1 (issue #11): `longSide(pieces:)`.
        public var pieces: Double
        public var eyes: Eyes
        public var mouth: Mouth
        public var ground: Ground
        public var panel: Panel
        /// The panel's centre in the photo's unit square (x right, y down).
        public var centre: SIMD2<Double>
        /// What the painter drew in Refine, in order (`Mark`): lines the rows follow, contours
        /// rubbed out, the gold ground brushed on or off.
        public var marks: [Mark]

        public init(pieces: Double = Recipe.standardPieces, eyes: Eyes = .asTheyLook, mouth: Mouth = .asInThePhoto,
                    ground: Ground = .picture, panel: Panel = .whole, centre: SIMD2<Double> = SIMD2(0.5, 0.5),
                    marks: [Mark] = []) {
            self.pieces = pieces; self.eyes = eyes; self.mouth = mouth; self.ground = ground
            self.panel = panel; self.centre = centre; self.marks = marks
        }

        /// The slider's position for the standard count (1024 px, the bundled mosaics' Standard).
        public static let standardPieces = log(2.0) / log(6.0)

        /// The positions of the bundled mosaics' three details (724, 1024 and 1448 px).
        public static let detailPieces: [Detail: Double] = [.fewer: 0, .standard: standardPieces, .more: log(4.0) / log(6.0)]

        /// The working long side for a position of the Pieces slider: equal steps multiply the
        /// number of tiles (which grows with the side squared) by the same factor, from half the
        /// standard count (724 px) to three times it (1774 px).
        public static func longSide(pieces: Double) -> Int {
            Int((1024 * (0.5 * pow(6, min(max(pieces, 0), 1))).squareRoot()).rounded())
        }

        /// How many times the standard count of tiles the slider asks for: 0.5 to 3.
        public static func multiple(pieces: Double) -> Double { 0.5 * pow(6, min(max(pieces, 0), 1)) }

        public var longSide: Int { Self.longSide(pieces: pieces) }

        /// The bundled detail this recipe's tiles are, when a bundled mosaic made from the whole
        /// picture with the default eyes and mouth stands for what the engine would make; nil
        /// otherwise. The ground and the gold marks change no tile's place (they are laid on:
        /// `laid`); a line or a contour rubbed out does.
        public var bundledDetail: Detail? {
            guard eyes == .asTheyLook, mouth == .asInThePhoto, panel == .whole,
                  !marks.contains(where: \.kind.movesTiles) else { return nil }
            return Self.detailPieces.first { abs($0.value - pieces) < 1e-6 }?.key
        }

        /// The engine's settings for a photo laid at `side` px on its long side: the recipe's eyes
        /// and mouth, and the pitches and joint scaled from the recipe's own size, so a smaller
        /// working size (a draft while a slider moves) lays about as many tiles, more finely.
        public func settings(side: Int) -> Settings {
            var s = Settings()
            s.eyes = eyes
            s.mouth = mouth
            let k = Float(side) / Float(longSide)
            guard k < 1 else { return s }
            s.pitch *= k
            s.facePitch *= k
            s.grout = Swift.max(1, Int((Float(s.grout) * k).rounded()))
            return s
        }

        /// The mosaic as this recipe lays it: with its background in gold, for the gold ground,
        /// and the gold marks' tiles added to it or taken off (`goldTiles`).
        public func laid(_ mosaic: Mosaic) -> Mosaic {
            guard marks.contains(where: { !$0.kind.movesTiles }) else { return ground == .gold ? mosaic.goldGround() : mosaic }
            return mosaic.goldGround(goldTiles(of: mosaic))
        }

        private enum CodingKeys: String, CodingKey { case pieces, eyes, mouth, ground, panel, centre, marks }

        /// One of `marks` as read: nil when it doesn't (`Mark.init(from:)`), so the others are kept.
        private struct ReadMark: Decodable {
            let mark: Mark?
            init(from decoder: any Decoder) throws { mark = try? Mark(from: decoder) }
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Recipe()
            func raw<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
                ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil).flatMap(T.init(rawValue:)) ?? fallback
            }
            let p = (try? c.decodeIfPresent(Double.self, forKey: .pieces)) ?? nil
            pieces = p.map { $0.isFinite ? min(max($0, 0), 1) : d.pieces } ?? d.pieces
            eyes = raw(.eyes, d.eyes)
            mouth = raw(.mouth, d.mouth)
            ground = raw(.ground, d.ground)
            panel = raw(.panel, d.panel)
            let xy = ((try? c.decodeIfPresent([Double].self, forKey: .centre)) ?? nil) ?? []
            centre = xy.count == 2 && xy.allSatisfy(\.isFinite)
                ? SIMD2(min(max(xy[0], 0), 1), min(max(xy[1], 0), 1)) : d.centre
            marks = ((try? c.decodeIfPresent([ReadMark].self, forKey: .marks)) ?? nil)?.compactMap(\.mark) ?? []
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pieces, forKey: .pieces)
            try c.encode(eyes.rawValue, forKey: .eyes)
            try c.encode(mouth.rawValue, forKey: .mouth)
            try c.encode(ground.rawValue, forKey: .ground)
            try c.encode(panel.rawValue, forKey: .panel)
            try c.encode([centre.x, centre.y], forKey: .centre)
            // Written only once there are some: a recipe never refined reads as it always has.
            if !marks.isEmpty { try c.encode(marks, forKey: .marks) }
        }
    }

    /// The picture's background as it is, or laid in gold smalti, as behind the figures at Ravenna
    /// and in the icons (`Mosaic.goldGround`).
    nonisolated public enum Ground: String, Sendable, Hashable, CaseIterable {
        case picture, gold
    }

    /// How much of the photo goes on the wall: the whole of it, or a panel of a chosen shape the
    /// painter slides over it, as a setter squares off the part of a cartoon they'll lay.
    nonisolated public enum Panel: String, Sendable, Hashable, CaseIterable {
        case whole, square, upright, wide

        /// Width over height, or nil for the photo's own.
        public var aspect: Double? {
            switch self {
            case .whole: nil
            case .square: 1
            case .upright: 4.0 / 5
            case .wide: 3.0 / 2
            }
        }

        /// The panel in the photo's unit square (the photo `width` by `height`, any units), as large
        /// as fits, its centre at `centre` as far as the photo allows: (x, y, width, height).
        public func rect(width: Double, height: Double, centre: SIMD2<Double>) -> (x: Double, y: Double, width: Double, height: Double) {
            guard let aspect, width > 0, height > 0 else { return (0, 0, 1, 1) }
            let photo = width / height
            let w = aspect < photo ? aspect / photo : 1, h = aspect < photo ? 1 : photo / aspect
            let x = min(max(centre.x - w / 2, 0), 1 - w), y = min(max(centre.y - h / 2, 0), 1 - h)
            return (x, y, w, h)
        }
    }
}

nonisolated extension MosaicEngine.Face {
    /// The face with every coordinate and length multiplied by `k`: its features for the photo
    /// scaled by `k` (they are found once, at one size, and laid at another).
    public func scaled(by k: Float) -> MosaicEngine.Face {
        MosaicEngine.Face(box: box.map { $0 * k }, eyes: eyes.map { $0.map { $0 * k } },
                          lines: lines.map { .init(kind: $0.kind, pts: $0.pts.map { $0.map { $0 * k } }) })
    }
}
