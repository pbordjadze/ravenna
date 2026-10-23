nonisolated public extension MakingOf {
    /// The show's creative forks: options until Paul narrows them.
    nonisolated struct Options: Sendable, Equatable, Codable {
        /// The drawing's colour: Ravenna's red earth or Hagia Sophia's indigo.
        nonisolated public enum Sinopia: String, Sendable, Codable, CaseIterable { case red, indigo }
        /// One stage after another with a card each, or one build that quickens, its cards following
        /// the stage being set.
        nonisolated public enum Flow: String, Sendable, Codable, CaseIterable { case scenes, continuous }

        public var sinopia: Sinopia
        /// The setter's hand shown pressing each tile home.
        public var hand: Bool
        public var flow: Flow
        /// The cards name the makers (the closing card's four, Dioskourides on the face's). On since
        /// Paul's "Name them!" (October 23); off, they credit the works without the names.
        public var names: Bool

        public init(sinopia: Sinopia = .red, hand: Bool = false, flow: Flow = .scenes, names: Bool = true) {
            self.sinopia = sinopia; self.hand = hand; self.flow = flow; self.names = names
        }
    }

    /// A scene's card: the technique's name, a line on it, and who is credited. Every claim has its
    /// source in docs/making-of.md; never add a name without one.
    nonisolated struct Card: Sendable, Equatable {
        public var title: String
        public var line: String
        public var credit: String
        /// The algorithm Ravenna uses for the step, credited like the technique (empty for the model
        /// and the closing card).
        public var method: String

        /// The card for `scene`; the model's card carries the picture's own title and credit.
        public init(_ scene: Scene, options: Options = Options(), modelTitle: String = "", modelCredit: String = "") {
            method = Self.method(scene)
            switch scene {
            case .model:
                (title, line, credit) = ("The model", modelTitle, modelCredit)
            case .smalti:
                (title, line, credit) = (
                    "Smalti",
                    "Glass coloured with copper, cobalt, iron, antimony and tin, poured as a cake, then cut into tesserae.",
                    "Anonymous glassmakers; where they worked is still unknown")
            case .sinopia:
                (title, line, credit) = (
                    "The drawing on the bed",
                    "The design is drawn on the plaster first. At Classe, the drawing under the apse shows a different design from the one that was set.",
                    "Sant'Apollinare in Classe, Ravenna, 6th century; anonymous")
            case .bed:
                (title, line, credit) = (
                    "The painted bed",
                    "Each fresh patch of the bed is painted in full colour, \u{201C}a finished painting in true fresco\u{201D}, before a tile is set.",
                    "Hagia Sophia, recorded by Thomas Whittemore, 1942")
            case .face:
                (title, line, credit) = (
                    "Opus vermiculatum",
                    "The face in the smallest pieces, the eyes set as pieces of their own, row curving round row.",
                    options.names ? "As in the panels Dioskourides of Samos signed in tiny tesserae, Pompeii"
                        : "As in the signed panels in tiny tesserae from Pompeii")
            case .outlines:
                (title, line, credit) = (
                    "The outlines",
                    "Rows set first along the drawing\u{2019}s lines: \u{201C}the outline of the wing is shown by a row\u{201D}.",
                    "Hagia Sophia, the Deesis; anonymous")
            case .andamento:
                (title, line, credit) = (
                    "Andamento",
                    "Each row carries on the curve of the one before, so the rows show how the form moves.",
                    "Italian for \u{2018}the way it goes\u{2019}, a workshop word, not an ancient one")
            case .light:
                (title, line, credit) = (
                    "Set at a tilt",
                    "Gold and glass set at slightly different angles, each catching the light its own way.",
                    "Hagia Sophia; the Nativity, Bethlehem")
            case .hold where options.names:
                (title, line, credit) = (
                    "The makers",
                    "A few names survive: Sosus at Pergamon, Gnosis at Pella, Dioskourides of Samos, Ephraim at Bethlehem. Most mosaicists are anonymous.",
                    "Pliny, Natural History 36.184, and the works they signed")
            case .hold:
                (title, line, credit) = (
                    "The makers",
                    "Most mosaicists are anonymous; a few names survive.",
                    "No source read names the mosaicists of Ravenna or Hagia Sophia")
            }
        }

        /// Under each card, the algorithm for that step (Paul: "what algorithms we're using too").
        /// Sources: docs/making-of.md, "The algorithms".
        static func method(_ scene: Scene) -> String {
            switch scene {
            case .smalti: "The smalti chosen by k-means++ (David Arthur and Sergei Vassilvitskii, 2007) in Björn Ottosson’s OKLab (2020)"
            case .sinopia: "The lines found by HED edge detection (Saining Xie and Zhuowen Tu, 2015), retrained for ControlNet by Lvmin Zhang"
            case .bed: "The bed’s colours: a Gaussian blur of the tiles’ own"
            case .face: "The features found by face landmarks: Apple’s Vision, or Google’s MediaPipe for the works that came with the app"
            case .outlines: "The lines thinned to single rows by Zhang–Suen thinning (T. Y. Zhang and C. Y. Suen, 1984)"
            case .andamento: "Each row a level of a distance transform (Pedro Felzenszwalb and Daniel Huttenlocher, 2012)"
            case .light: "Each tile’s tilt from SplitMix64’s mixer (Guy Steele, Doug Lea and Christine Flood, 2014)"
            case .model, .hold: ""
            }
        }
    }
}
