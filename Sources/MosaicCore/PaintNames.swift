import PaintCore

/// Ravenna's names for a mosaic's paints ("12 · Giallo Antico"): the stones, glass, metals and
/// pigments of Roman and Byzantine mosaic and wall painting, each with its source in
/// docs/paint-names.md (issue #16). They take the place of Paint by Moonlight's nicknames through
/// PaintCore's own door for a custom table (`ColorNickname.Vocabulary(table:)` and its seeded
/// draw), so the names are derived at load, never stored, and the same painting always reads the
/// same.
public enum PaintNames {
    /// One entry per line: the sRGB hex of the material's colour, then its name. PaintCore's style
    /// guide holds (`Vocabulary.problems()`: one or two Title Case words, at most 16 characters,
    /// no colour word on a colour of another family), except its size and gamut checks, which are
    /// for a vocabulary that names every colour: a colour with no material near keeps its
    /// structured name ("Dark green").
    ///
    /// Frozen once shipped: its order breaks distance ties and takes part in the seeded draw, so a
    /// change is a new table and a version recorded per artwork, never an edit of this one.
    public static let table = """
    """

    public static let vocabulary = ColorNickname.Vocabulary(table: table)

    private static let names = Set(vocabulary.entries.map(\.name))

    /// The palette's names, index-aligned and unique within it: nil for a paint with no material
    /// within `ColorNickname.maximumDistance` (or none left), which keeps its structured name.
    public static func names(for palette: [PaletteColor], seed: UInt64) -> [String?] {
        ColorNickname.assign(palette, seed: seed, vocabulary: vocabulary).map { names.contains($0) ? $0 : nil }
    }
}
