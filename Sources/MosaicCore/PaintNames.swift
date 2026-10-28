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
    D4B071 Giallo Antico
    533426 Rosso Antico
    3A3B30 Nero Antico
    4A5042 Verde Antico
    6A6B64 Bigio Antico
    333831 Bigio Morato
    9F998A Pavonazzetto
    9D9779 Cipollino
    5C473B Cipollino Rosso
    615D4C Africano
    A8886D Portasanta
    C29E85 Marmor Sagarium
    6F6053 Semesanto
    C3AF8E Lumachella
    A68D57 Astracane Dorato
    B1AE93 Cotognino
    977F4D Alabastrites
    8C5E58 Porphyrites
    504B3E Porfido Bigio
    363B2C Porfido Nero
    3E4332 Porfido Verde
    3B4731 Lacedaemonian
    6F5A42 Syenites
    212A1F Granito Nero
    4B5140 Ofite
    30362A Gabbro Eufotide
    404235 Basanites
    33372B Lydian Stone
    393B32 Lavagna Antica
    4F4C3B Selce
    D7C8A7 Travertino
    E5D7B6 Palombino
    FCFAEA Carrara
    FAF4DF Thasian Marble
    F3EFDE Pentelic Marble
    94968F Proconnesian
    85857C Greco Scritto
    7A6636 Arenaria Antica
    464634 Pudingo Antico
    643625 Porporina
    AD9278 Cottanello
    5A4523 Aventurine
    1D2134 Lapis Lazuli
    3D607B Sapphiros
    54484F Amethyst
    534434 Agata
    AEA68F Chalcedony
    0E100F Obsidian
    3E3A37 Gagates
    1C1B19 Lucullan Marble
    6F3622 Carnelian
    B8764B Sarda
    873836 Red Jasper
    3A5D4E Iaspis
    2D2F37 Heliotropium
    25885C Smaragdus
    494F5C Nicolo
    53594F Steatite
    82857C Serpentine
    454A37 Verde Ranocchia
    1C1A18 Atramentum
    2A211B Tryginon
    1E1914 Elephantinon
    100E10 Charcoal Black
    1C1D1F Vine Black
    2E2722 Ampelitis
    3E2218 Exudra
    4A2E1A Burnt Umber
    5E4B32 Umber
    6A5C4C Posc
    4F4E3A Proplasmos
    B09070 Glykasmos
    D4A487 Sarka
    E2B898 Membrina
    F0DCC6 Lumina
    6E6E6E Veneda
    1F3B34 Prasinus
    5B6B34 Succus
    6E5A88 Manisc
    7C3A6C Folium
    13306E Lazur
    3F8A5C Spanish Green
    5E9C72 Salt Green
    B2B2B0 Tin Leaf
    E1C06A Cerussa Usta
    A43A22 Sinopis
    8C3B25 Cicerculum
    833923 Rubrica
    9A4A2E Miltos
    B24A2E Lemnian Earth
    A5482E Red Ochre
    7A2E20 Hematite
    8A3A28 Usta
    B03A26 Sandyx
    A9472E Syricum
    8E4B32 Bole
    BE3322 Cinnabaris
    DC4A2C Red Lead
    F07A2E Sandarach
    E8B533 Orpiment
    C0913F Sil
    D8AD5C Attic Sil
    8D6A3C Scyric Sil
    C8A24C Yellow Ochre
    E7C387 Attic Ochre
    C9833F Orange Ochre
    A27940 Goethite
    C2AA62 Jarosite
    C49A4C Quaestorian Leaf
    CDA557 Beeswax
    E9DFC4 Punic Wax
    F2EEE4 Lead White
    E8E2D3 Melinum
    F3F1EA Paraetonium
    EEEDE7 Chalk
    F4F2EC Gypsum
    D6D0C8 Cimolian Earth
    E5E3DE Argentaria
    7E8466 Green Earth
    8A9272 Theodotion
    8FA078 Appianum
    6F9A3E Chrysocolla
    3E8F7E Verdigris
    2E8B5A Malachite
    2468A8 Egyptian Blue
    2E86B0 Caeruleum
    74BCD8 Lomentum
    5B8FC4 Armenium
    1F4C98 Azurite
    18223F Indicum
    A2567E Purpurissum
    6A2450 Ostrum
    4A2148 Tyrian Purple
    6C4A7C Vaccinium
    C24F6A Madder Lake
    E4BD59 Gold Tessera
    DBAC36 Gold Leaf
    D1982B Greek Glass
    CBAA7C Electrum
    E0D4C5 Silver Tessera
    C4B8A4 Silver Leaf
    C2C2B3 Cartellina
    8E8386 Stannum
    1A827D Smalti
    41466E Sapphire Glass
    041B56 Cobalt Glass
    282828 Obsian Glass
    1C1A1F Black Paste
    4B6174 Blue Paste
    8C6810 Amber Glass
    A7BEBD Natron Glass
    1984A4 Opaque Turquoise
    EEE8E0 Opaque White
    376643 Copper Green
    EDC053 Lead Antimonate
    E1BC33 Lead Stannate
    D8980C Orange Tessera
    963528 Haematinum
    C14231 Cuprite
    BC4437 Sealing-wax Red
    6B5756 Manganese
    AA3F1B Terracotta
    815C46 Cocciopesto
    A36E61 Opus Signinum
    AF8A81 Opus Figlinum
    7C7C6E Opus Spicatum
    A8A994 Lime Mortar
    98917E Mortar Pavement
    74726C Pebble
    3DD1E4 Faience
    485474 Cloisonne Enamel
    A87D40 Limewood
    B3A27C Linen
    CEAF85 Shell
    """

    public static let vocabulary = ColorNickname.Vocabulary(table: table)

    private static let names = Set(vocabulary.entries.map(\.name))

    /// The palette's names, index-aligned and unique within it: nil for a paint with no material
    /// within `ColorNickname.maximumDistance` (or none left), which keeps its structured name.
    public static func names(for palette: [PaletteColor], seed: UInt64) -> [String?] {
        ColorNickname.assign(palette, seed: seed, vocabulary: vocabulary).map { names.contains($0) ? $0 : nil }
    }
}
