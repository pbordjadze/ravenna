import PaintCore

/// Ravenna's names for a painting's paints ("12 · Giallo Antico"): the stones, glass, metals and
/// pigments of Roman and Byzantine mosaic and wall painting, and a few materials of their world
/// (Egyptian faience, the Fayum portraits' limewood and linen), each with its source in
/// docs/paint-names.md (issue #16). They take the place of Paint by Moonlight's nicknames through
/// PaintCore's own door for a custom table (`ColorNickname.Vocabulary(table:)` and its seeded
/// draw), so the names are derived at load, never stored, and the same painting always reads the
/// same.
public enum PaintNames {
    /// Each material's credit, in `table`'s order, for Settings › Acknowledgements.
    public struct Credit: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable { case stone, pigment, glass }
        public let name: String
        /// sRGB, 0xRRGGBB: the colour the name is drawn for.
        public let hex: UInt32
        public let kind: Kind
        /// What the material is, as its source says (English).
        public let what: String
        /// Author, work and book or section, or the museum or collection.
        public let citation: String
        /// The source's page, where it has one.
        public let link: String?

        public var id: String { name }
    }

    // `table` (PaintNamesTable.swift, written by tools/paint_names.py from docs/paint-names.json):
    // one entry per line, the sRGB hex of the material's colour, then its name. PaintCore's style
    // guide holds (`Vocabulary.problems()`: one or two Title Case words, at most 16 characters, no
    // English colour word on a colour of another family; the Italian and Latin ones, "Rosso",
    // "Verde", go unchecked), except its size and gamut checks, which are for a vocabulary that
    // names every colour: a colour with no material near keeps its structured name ("Dark green").
    //
    // Frozen once shipped: its order breaks distance ties and takes part in the seeded draw, so a
    // change is a new table and a version recorded per artwork (absent meaning this one), never an
    // edit of this one; `names(for:seed:)` and `maximumDistance` freeze with it. The draw is
    // PaintCore's v1 (Float `exp`): the same on every launch of one platform, but Linux's names may
    // differ from the device's.

    public static let vocabulary = ColorNickname.Vocabulary(table: table)

    private static let entries = Dictionary(uniqueKeysWithValues: vocabulary.entries.map { ($0.name, $0) })

    /// How far (ΔE, OKLab) a paint's material may be from it: about four just-noticeable
    /// differences. PaintCore's draw reaches 0.12, where a vivid yellow-green drew "Gold Leaf";
    /// a paint no real material comes this near keeps its plain name rather than a stretched one
    /// (October 28: no name that isn't the paint's).
    public static let maximumDistance: Float = 0.08

    /// The palette's names, index-aligned and unique within it: PaintCore's seeded draw where it
    /// lands within `maximumDistance`; else, in palette order, the nearest material within it that
    /// no other paint has (the draw can land past the cutoff, or move a paint to a farther material
    /// when its own are taken); else nil, and the paint keeps its structured name. Frozen with
    /// `table` once shipped: saved paintings' names depend on both.
    public static func names(for palette: [PaletteColor], seed: UInt64) -> [String?] {
        func near(_ paint: PaletteColor, _ entry: ColorNickname.Entry) -> Bool {
            ColorScience.distance(paint.oklab, entry.oklab) <= maximumDistance
        }
        var names: [String?] = zip(palette, ColorNickname.assign(palette, seed: seed, vocabulary: vocabulary)).map { paint, name in
            guard let entry = entries[name], near(paint, entry) else { return nil }
            return name
        }
        var taken = Set(names.compactMap { $0 })
        for (index, paint) in palette.enumerated() where names[index] == nil {
            let nearest = vocabulary.entries
                .filter { !taken.contains($0.name) && near(paint, $0) }
                .min { ColorScience.distance(paint.oklab, $0.oklab) < ColorScience.distance(paint.oklab, $1.oklab) }
            if let nearest {
                names[index] = nearest.name
                taken.insert(nearest.name)
            }
        }
        return names
    }
}
