// Written by tools/paint_names.py from docs/paint-names.json: edit the JSON and run it.

extension PaintNames {
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
    98A152 Topazos
    ADBD6C Pyrochlore
    56703C Green Tessera
    E6D23C Luteum
    296E29 Weld Green
    F0BE3A Crocus
    4A191A Carbunculus
    A8202E Coccum
    7A1C32 Hysginum
    E17E4A Curalium
    58758A Glastum
    24343F Vitrum
    7B949A Beryl
    B7BDA8 Callaina
    8A5C78 Conchyliatum
    """

    public static let credits: [Credit] = [
        Credit(name: "Giallo Antico", hex: 0xD4B071, kind: .stone,
               what: "Numidian yellow marble (marmor Numidicum) from Chemtou, Tunisia; Pliny dates its first use at Rome to the consul Lepidus (thresholds).",
               citation: "Corsi Collection no. 25, Oxford University Museum of Natural History; Pliny, Natural History 36.8",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/25"),
        Credit(name: "Rosso Antico", hex: 0x533426, kind: .stone,
               what: "Dark red marble from Cape Matapan (Mani, Laconia); museum: most stone was quarried in Roman times.",
               citation: "Corsi Collection no. 61, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/61"),
        Credit(name: "Nero Antico", hex: 0x3A3B30, kind: .stone,
               what: "Black marble; museum: this specimen most probably from ancient quarries at Jebel Aziza, Tunisia; Corsi: held in great esteem under Rome.",
               citation: "Corsi Collection no. 71, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/71"),
        Credit(name: "Verde Antico", hex: 0x4A5042, kind: .stone,
               what: "Serpentinite breccia from Larissa, Thessaly (marmor Atracium); quarries closed from Justinian until c.1900.",
               citation: "Corsi Collection no. 565, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/565"),
        Credit(name: "Bigio Antico", hex: 0x6A6B64, kind: .stone,
               what: "Grey ancient marble (bigio brecciato); museum: source likely Greece or Turkey.",
               citation: "Corsi Collection no. 142, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/142"),
        Credit(name: "Bigio Morato", hex: 0x333831, kind: .stone,
               what: "Very dark grey limestone; museum: possibly from ancient quarries of bigio morato and nero antico on NE Chios.",
               citation: "Corsi Collection no. 140, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/140"),
        Credit(name: "Pavonazzetto", hex: 0x9F998A, kind: .stone,
               what: "Phrygian marble from Iscehisar (Synnada/Docimium), Turkey: white clasts in purple-red matrix; quarried 1st c. BC to 6th c. AD.",
               citation: "Corsi Collection no. 123, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/123"),
        Credit(name: "Cipollino", hex: 0x9D9779, kind: .stone,
               what: "Cipollino verde from Karystos, Euboea: banded green marble brought to Rome from 2nd c. BC to 7th c. AD.",
               citation: "Corsi Collection no. 89, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/89"),
        Credit(name: "Cipollino Rosso", hex: 0x5C473B, kind: .stone,
               what: "Marmor Iasense / Carium from Iasos, Caria (Turkey); used in Hagia Sophia and San Vitale, Ravenna.",
               citation: "Corsi Collection no. 95, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/95"),
        Credit(name: "Africano", hex: 0x615D4C, kind: .stone,
               what: "Tectonic breccia from Sigacik (ancient Teos), Turkey; large quantities used in Italy and North Africa.",
               citation: "Corsi Collection no. 102, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/102"),
        Credit(name: "Portasanta", hex: 0xA8886D, kind: .stone,
               what: "Pink breccia from Chios, quarried by the Romans from 1st c. BC until the quarries closed in Byzantine times.",
               citation: "Corsi Collection no. 77, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/77"),
        Credit(name: "Marmor Sagarium", hex: 0xC29E85, kind: .stone,
               what: "Breccia corallina from Vezirhan, Bilecik (ancient Bithynia), Turkey.",
               citation: "Corsi Collection no. 404, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/404"),
        Credit(name: "Semesanto", hex: 0x6F6053, kind: .stone,
               what: "Small-clast breccia from Skyros (breccia di Sciro).",
               citation: "Corsi Collection no. 409, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/409"),
        Credit(name: "Lumachella", hex: 0xC3AF8E, kind: .stone,
               what: "Shell limestone (lumachella bianca antica, marmor Megarense) from Megara, Attica.",
               citation: "Corsi Collection no. 215, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/215"),
        Credit(name: "Astracane Dorato", hex: 0xA68D57, kind: .stone,
               what: "Ancient lumachella from Thuburbo Maius (Henchir Kasbat), Tunisia.",
               citation: "Corsi Collection no. 223, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/223"),
        Credit(name: "Cotognino", hex: 0xB1AE93, kind: .stone,
               what: "Egyptian alabaster (alabastro cotognino), banded calcite from Hatnub and other Nile valley quarries.",
               citation: "Corsi Collection no. 294, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/294"),
        Credit(name: "Alabastrites", hex: 0x977F4D, kind: .stone,
               what: "Pliny's onyx/alabastrites, hollowed into unguent vessels; also used for columns at Rome.",
               citation: "Pliny, Natural History 36.12",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=12"),
        Credit(name: "Porphyrites", hex: 0x8C5E58, kind: .stone,
               what: "Imperial porphyry of Egypt (Gebel Dokhan, Mons Porphyrites), quarried 1st-5th c. AD.",
               citation: "Pliny, Natural History 36.11; The Met, object 256126; Corsi Collection no. 783, Oxford University Museum of Natural History",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=11"),
        Credit(name: "Porfido Bigio", hex: 0x504B3E, kind: .stone,
               what: "Grey variety of imperial porphyry, Gebel Dokhan, Egypt.",
               citation: "Corsi Collection no. 786, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/786"),
        Credit(name: "Porfido Nero", hex: 0x363B2C, kind: .stone,
               what: "Black variety of imperial porphyry, Gebel Dokhan, Egypt.",
               citation: "Corsi Collection no. 788, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/788"),
        Credit(name: "Porfido Verde", hex: 0x3E4332, kind: .stone,
               what: "Green porphyry (lapis hieracites), Gebel Dokhan, Egypt.",
               citation: "Corsi Collection no. 787, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/787"),
        Credit(name: "Lacedaemonian", hex: 0x3B4731, kind: .stone,
               what: "Green porphyry of Krokees, Laconia (porfido serpentino); reused in Cosmati pavements.",
               citation: "Pliny, Natural History 36.11",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=11"),
        Credit(name: "Syenites", hex: 0x6F5A42, kind: .stone,
               what: "Aswan granite (granito rosso antico, sienite) from Syene, Nile valley; Corsi: columns of S. Maria degli Angeli.",
               citation: "Pliny, Natural History 36.13",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=13"),
        Credit(name: "Granito Nero", hex: 0x212A1F, kind: .stone,
               what: "Black Aswan granodiorite (diorite Egiziano), Nile valley, Egypt.",
               citation: "Corsi Collection no. 836, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/836"),
        Credit(name: "Ofite", hex: 0x4B5140, kind: .stone,
               what: "Egyptian metagabbro from Wadi Umm Wikala (granito della Sedia), also called ofite.",
               citation: "Corsi Collection no. 821, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/821"),
        Credit(name: "Gabbro Eufotide", hex: 0x30362A, kind: .stone,
               what: "Egyptian gabbro from Wadi Maghrabiya, Eastern Desert.",
               citation: "Corsi Collection no. 989, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/989"),
        Credit(name: "Basanites", hex: 0x404235, kind: .stone,
               what: "Pliny's dark Egyptian stone for sculpture (Nile group, Temple of Peace).",
               citation: "Pliny, Natural History 36.11",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=11"),
        Credit(name: "Lydian Stone", hex: 0x33372B, kind: .stone,
               what: "Touchstone (pietra di paragone, marmor Lydium) for testing gold.",
               citation: "Corsi Collection no. 671, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/671"),
        Credit(name: "Lavagna Antica", hex: 0x393B32, kind: .stone,
               what: "Slaty stone found in excavations at Rome, identified by Corsi with Pliny's Theban stone.",
               citation: "Corsi Collection no. 560, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/560"),
        Credit(name: "Selce", hex: 0x4F4C3B, kind: .stone,
               what: "Lava from Capo di Bove near Rome, used for paving and walls.",
               citation: "Corsi Collection no. 668, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/668"),
        Credit(name: "Travertino", hex: 0xD7C8A7, kind: .stone,
               what: "Travertine of Tivoli (marmor Tiburtinum), building stone of Rome since antiquity (Colosseum).",
               citation: "Corsi Collection no. 14, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/14"),
        Credit(name: "Palombino", hex: 0xE5D7B6, kind: .stone,
               what: "Fine white-grey limestone (palombino antico), Corsi's marmor Coraliticum.",
               citation: "Corsi Collection no. 13, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/13"),
        Credit(name: "Carrara", hex: 0xFCFAEA, kind: .stone,
               what: "White marble of Luni/Carrara (marmor Lunense), used by the ancients for statues and architecture.",
               citation: "Corsi Collection no. 9, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/9"),
        Credit(name: "Thasian Marble", hex: 0xFAF4DF, kind: .stone,
               what: "Dolomitic statuary marble from Cape Vathy, Thasos.",
               citation: "Corsi Collection no. 5, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/5"),
        Credit(name: "Pentelic Marble", hex: 0xF3EFDE, kind: .stone,
               what: "Fine white marble of Mt Pentelikon, Attica, for Greek architecture and statuary.",
               citation: "Corsi Collection no. 3, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/3"),
        Credit(name: "Proconnesian", hex: 0x94968F, kind: .stone,
               what: "Coarse white marble with grey banding from Marmara island, Turkey.",
               citation: "Corsi Collection no. 4, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/4"),
        Credit(name: "Greco Scritto", hex: 0x85857C, kind: .stone,
               what: "White marble with dark \"writing\" from Hippo Regius (Annaba), Algeria, worked 1st-3rd c. AD.",
               citation: "Corsi Collection no. 99, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/99"),
        Credit(name: "Arenaria Antica", hex: 0x7A6636, kind: .stone,
               what: "Limestone Corsi called arenaria antica, \"found in excavations\".",
               citation: "Corsi Collection no. 557, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/557"),
        Credit(name: "Pudingo Antico", hex: 0x464634, kind: .stone,
               what: "Ancient conglomerate (puddingstone), quarry unknown.",
               citation: "Corsi Collection no. 681, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/681"),
        Credit(name: "Porporina", hex: 0x643625, kind: .stone,
               what: "Red stone found in the excavations of Hadrian's Villa, Tivoli.",
               citation: "Corsi Collection no. 63, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/63"),
        Credit(name: "Cottanello", hex: 0xAD9278, kind: .stone,
               what: "Red-purple marble; museum cites Borghini that ancient cottanello resembles the Sabine stone.",
               citation: "Corsi Collection no. 187, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/187"),
        Credit(name: "Aventurine", hex: 0x5A4523, kind: .stone,
               what: "Ferruginous sandstone, perhaps from Roman quarries in the Nile valley; Corsi cut it from an Egyptian statue fragment.",
               citation: "Corsi Collection no. 720, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/720"),
        Credit(name: "Lapis Lazuli", hex: 0x1D2134, kind: .stone,
               what: "Lazurite rock from Badakhshan, Afghanistan; Corsi identifies Pliny's cyanus with it.",
               citation: "Corsi Collection no. 703, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/703"),
        Credit(name: "Sapphiros", hex: 0x3D607B, kind: .stone,
               what: "Pliny's blue gem with gold spots, which the Bostock-Riley note identifies as lapis lazuli.",
               citation: "Pliny, Natural History 37.39",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=39"),
        Credit(name: "Amethyst", hex: 0x54484F, kind: .stone,
               what: "Violet quartz; Pliny's amethystos of India, Arabia, Egypt.",
               citation: "Corsi Collection no. 712, Oxford University Museum of Natural History; Pliny, Natural History 37.40",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/712"),
        Credit(name: "Agata", hex: 0x534434, kind: .stone,
               what: "Chalcedony with pink jasper inclusions (Corsi's agata); Pliny's achates first found in Sicily.",
               citation: "Corsi Collection no. 728, Oxford University Museum of Natural History; Pliny, Natural History 37.54",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/728"),
        Credit(name: "Chalcedony", hex: 0xAEA68F, kind: .stone,
               what: "White translucent chalcedony (cryptocrystalline quartz).",
               citation: "Corsi Collection no. 724, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/724"),
        Credit(name: "Obsidian", hex: 0x0E100F, kind: .stone,
               what: "Volcanic glass; Pliny's Obsian stone, of which he saw solid statues of Augustus.",
               citation: "Corsi Collection no. 670, Oxford University Museum of Natural History; Pliny, Natural History 36.67",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/670"),
        Credit(name: "Gagates", hex: 0x3E3A37, kind: .stone,
               what: "Jet, from Gages in Lycia (Pliny).",
               citation: "Pliny, Natural History 36.34",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=34"),
        Credit(name: "Lucullan Marble", hex: 0x1C1B19, kind: .stone,
               what: "Black marble introduced at Rome by L. Lucullus; Pliny says found on Melos (variant reading Chios).",
               citation: "Pliny, Natural History 36.8",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=8"),
        Credit(name: "Carnelian", hex: 0x6F3622, kind: .stone,
               what: "Red chalcedony for Roman ring stones; Bostock-Riley identify Pliny's sarda as carnelian.",
               citation: "The Met, object 245017; Pliny, Natural History 37.31",
               link: "https://www.metmuseum.org/art/collection/search/245017"),
        Credit(name: "Sarda", hex: 0xB8764B, kind: .stone,
               what: "Pliny's sarda, \"first found at Sardes\", the commonest ancient engraved gem.",
               citation: "Pliny, Natural History 37.31",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=31"),
        Credit(name: "Red Jasper", hex: 0x873836, kind: .stone,
               what: "Red jasper ring stones, Roman.",
               citation: "The Met, object 245047",
               link: "https://www.metmuseum.org/art/collection/search/245047"),
        Credit(name: "Iaspis", hex: 0x3A5D4E, kind: .stone,
               what: "Pliny's iaspis (jasper), green; that of Cyprus \"of a full sea-green\".",
               citation: "Pliny, Natural History 37.37",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=37"),
        Credit(name: "Heliotropium", hex: 0x2D2F37, kind: .stone,
               what: "Bloodstone: leek-green jasper with red veins (Pliny).",
               citation: "Pliny, Natural History 37.60",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=60"),
        Credit(name: "Smaragdus", hex: 0x25885C, kind: .stone,
               what: "Pliny's emerald, third rank among gems.",
               citation: "Pliny, Natural History 37.16",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=16"),
        Credit(name: "Nicolo", hex: 0x494F5C, kind: .stone,
               what: "Banded onyx with a bluish-white layer over black, Roman ring stones.",
               citation: "The Met, object 254692",
               link: "https://www.metmuseum.org/art/collection/search/254692"),
        Credit(name: "Steatite", hex: 0x53594F, kind: .stone,
               what: "Soft stone carved into Byzantine icons.",
               citation: "The Met, object 330100",
               link: "https://www.metmuseum.org/art/collection/search/330100"),
        Credit(name: "Serpentine", hex: 0x82857C, kind: .stone,
               what: "Serpentine carved into Byzantine pendants.",
               citation: "The Met, object 466072",
               link: "https://www.metmuseum.org/art/collection/search/466072"),
        Credit(name: "Verde Ranocchia", hex: 0x454A37, kind: .stone,
               what: "Serpentinite, most likely from Wadi Umm Esh, Eastern Desert, Egypt.",
               citation: "Corsi Collection no. 578, Oxford University Museum of Natural History",
               link: "https://www.oum.ox.ac.uk/corsi/stones/view/578"),
        Credit(name: "Atramentum", hex: 0x1C1A18, kind: .pigment,
               what: "Roman black pigment, made chiefly from the soot of burnt resin or pitch (best from torch-pine); one of Apelles' four colors",
               citation: "Pliny, Natural History 35.25, 35.32",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=25"),
        Credit(name: "Tryginon", hex: 0x2A211B, kind: .pigment,
               what: "Black made by Polygnotus and Micon from grape-husks (wine-lees black)",
               citation: "Pliny, Natural History 35.25",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=25"),
        Credit(name: "Elephantinon", hex: 0x1E1914, kind: .pigment,
               what: "Black Apelles made from burnt ivory",
               citation: "Pliny, Natural History 35.25",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=25"),
        Credit(name: "Charcoal Black", hex: 0x100E10, kind: .pigment,
               what: "Carbon black from charred wood; found in the eyes, hair and background of a Fayum encaustic portrait",
               citation: "ColourLex, charcoal black; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017)",
               link: "https://colourlex.com/project/charcoal-black/"),
        Credit(name: "Vine Black", hex: 0x1C1D1F, kind: .pigment,
               what: "Carbon black from charred vine twigs; medieval tables list black 'from the charcoal of a soft wood, or of the vine'",
               citation: "ColourLex, vine black; Theophilus, De diversis artibus (tr. Hendrie, 1847), Hendrie’s note on Nigrum",
               link: "https://colourlex.com/project/vine-black/"),
        Credit(name: "Ampelitis", hex: 0x2E2722, kind: .pigment,
               what: "Earth strongly resembling bitumen; black, dissolves in oil like wax; used in medicines and hair dye",
               citation: "Pliny, Natural History 35.56",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=56"),
        Credit(name: "Exudra", hex: 0x3E2218, kind: .pigment,
               what: "Theophilus' dark relief color for faces: red with a little black, drawn round features",
               citation: "Theophilus, De diversis artibus 1.13 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Burnt Umber", hex: 0x4A2E1A, kind: .pigment,
               what: "Roasted umber (iron oxide with manganese), a warm dark brown in use since antiquity",
               citation: "ColourLex",
               link: "https://colourlex.com/project/burnt-umber/"),
        Credit(name: "Umber", hex: 0x5E4B32, kind: .pigment,
               what: "Manganese-rich brown earth; found in the Tebtunis mummy portraits; Byzantine manuals use it for drawing features",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; ColourLex, umber",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Posc", hex: 0x6A5C4C, kind: .pigment,
               what: "Theophilus' shadow tint for faces: flesh color mixed with deep green, burnt-ochre red and a little cinnabar",
               citation: "Theophilus, De diversis artibus 1.3 (tr. Hendrie, 1847), with Hendrie’s note on Posc",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Proplasmos", hex: 0x4F4E3A, kind: .pigment,
               what: "Byzantine undercoat for flesh: white, ochre, the green used for murals, and black",
               citation: "Dionysios of Fourna, Hermeneia §16 (tr. Parpulov, Dolgikh and Cowe, Dumbarton Oaks Papers 64, 2010)",
               link: "https://www.pallasweb.com/deesis/byzantine-text-technique-of-icon-painting.html"),
        Credit(name: "Glykasmos", hex: 0xB09070, kind: .pigment,
               what: "Byzantine blending tint: two parts flesh pigment to one part undercoat, laid on cheeks and chin",
               citation: "Dionysios of Fourna, Hermeneia §20-21 (tr. Parpulov, Dolgikh and Cowe, Dumbarton Oaks Papers 64, 2010)",
               link: "https://www.pallasweb.com/deesis/byzantine-text-technique-of-icon-painting.html"),
        Credit(name: "Sarka", hex: 0xD4A487, kind: .pigment,
               what: "Byzantine flesh pigment (sarka): white, ochre and cinnabar",
               citation: "Dionysios of Fourna, Hermeneia §18-19, 50 (tr. Parpulov, Dolgikh and Cowe, Dumbarton Oaks Papers 64, 2010)",
               link: "https://www.pallasweb.com/deesis/byzantine-text-technique-of-icon-painting.html"),
        Credit(name: "Membrina", hex: 0xE2B898, kind: .pigment,
               what: "Theophilus' basic color for faces and bodies: burnt (yellowed) ceruse mixed with white ceruse and cinnabar",
               citation: "Theophilus, De diversis artibus 1.1, 1.3 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Lumina", hex: 0xF0DCC6, kind: .pigment,
               what: "Theophilus' highlight: ground ceruse mixed with the simple flesh color",
               citation: "Theophilus, De diversis artibus 1.5 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Veneda", hex: 0x6E6E6E, kind: .pigment,
               what: "Theophilus' grey for the pupils: black mixed with a little white (lime on walls)",
               citation: "Theophilus, De diversis artibus 1.6 (tr. Hendrie, 1847), with Hendrie’s note on Veneda",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Prasinus", hex: 0x1F3B34, kind: .pigment,
               what: "Theophilus' prasinus: a preparation 'having the appearance of a green color with black', dissolved in water, used on new walls",
               citation: "Theophilus, De diversis artibus 1.2 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Succus", hex: 0x5B6B34, kind: .pigment,
               what: "Sap green: the green juice of plants, mixed with greens and black for shadows",
               citation: "Theophilus, De diversis artibus 1.14 (tr. Hendrie, 1847), with Hendrie’s note on Succus",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Manisc", hex: 0x6E5A88, kind: .pigment,
               what: "Theophilus' manisc (menesch), a violet ground for draperies, shaded with folium and lit with lazur",
               citation: "Theophilus, De diversis artibus 1.14 (tr. Hendrie, 1847), with Hendrie’s note on Manisc",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Folium", hex: 0x7C3A6C, kind: .pigment,
               what: "Plant color of three kinds (red, purple, blue) used for books and draperies; here the purple",
               citation: "Theophilus, De diversis artibus 1.35 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Lazur", hex: 0x13306E, kind: .pigment,
               what: "Theophilus' blue for draperies, lightened with white; Hendrie takes it for the deep-blue lapis armenus",
               citation: "Theophilus, De diversis artibus 1.14 (tr. Hendrie, 1847), with Hendrie’s note on Lazur",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Spanish Green", hex: 0x3F8A5C, kind: .pigment,
               what: "Copper green made by pouring warm vinegar on scraped copper plates",
               citation: "Theophilus, De diversis artibus 1.38 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Salt Green", hex: 0x5E9C72, kind: .pigment,
               what: "Copper green made with honey and salt on copper plates in an oak box under vinegar",
               citation: "Theophilus, De diversis artibus 1.37 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Tin Leaf", hex: 0xB2B2B0, kind: .pigment,
               what: "Polished tin foil laid on wood under oil colors for 'transparent' pictures",
               citation: "Theophilus, De diversis artibus 1.29 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Cerussa Usta", hex: 0xE1C06A, kind: .pigment,
               what: "Burnt ceruse: lead white heated until it turns yellow (massicot)",
               citation: "Theophilus, De diversis artibus 1.1 (tr. Hendrie, 1847), with Hendrie’s note on Flavus Color",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Sinopis", hex: 0xA43A22, kind: .pigment,
               what: "Red earth named after Sinope in Pontus; also from Egypt, the Balearics, Lemnos, Cappadocia; one of Apelles' four colors",
               citation: "Pliny, Natural History 35.13, 35.32",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=13"),
        Credit(name: "Cicerculum", hex: 0x8C3B25, kind: .pigment,
               what: "The African sinopis, sold cheaply",
               citation: "Pliny, Natural History 35.13",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=13"),
        Credit(name: "Rubrica", hex: 0x833923, kind: .pigment,
               what: "Red earth (red ochre); Egyptian and African kinds used for wood and painting",
               citation: "Pliny, Natural History 35.14-15",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=14"),
        Credit(name: "Miltos", hex: 0x9A4A2E, kind: .pigment,
               what: "The Greek name for red earth, with which Homer's ships were colored",
               citation: "Pliny, Natural History 33.38",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=38"),
        Credit(name: "Lemnian Earth", hex: 0xB24A2E, kind: .pigment,
               what: "Rubrica of Lemnos, sold in sealed packages ('sphragis'); used as an undercoat for minium",
               citation: "Pliny, Natural History 35.14",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=14"),
        Credit(name: "Red Ochre", hex: 0xA5482E, kind: .pigment,
               what: "Iron-oxide red earth; best from Sinope, Egypt, the Balearics and Lemnos; on the lips and beads of a Fayum portrait",
               citation: "Vitruvius, De architectura 7.7.2 (tr. Gwilt); ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Hematite", hex: 0x7A2E20, kind: .pigment,
               what: "Iron oxide; one of the iron earths behind nearly every tone in Tebtunis and Fayum portraits",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; Delaney et al., Scientific Reports 7 (2017)",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Usta", hex: 0x8A3A28, kind: .pigment,
               what: "Burnt ceruse (or calcined marbled sil quenched in vinegar); first used by Nicias; 'without usta shadows cannot be made'",
               citation: "Pliny, Natural History 35.20",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=20"),
        Credit(name: "Sandyx", hex: 0xB03A26, kind: .pigment,
               what: "Sandarach calcined with an equal part of rubrica; Davy thought it approached crimson",
               citation: "Pliny, Natural History 35.23",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=23"),
        Credit(name: "Syricum", hex: 0xA9472E, kind: .pigment,
               what: "Artificial color of sinopis with sandyx, used as an undercoat for minium",
               citation: "Pliny, Natural History 35.24",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=24"),
        Credit(name: "Bole", hex: 0x8E4B32, kind: .pigment,
               what: "Reddish clay; Byzantine painters used it with umber to draw features and to redden ochre for flesh",
               citation: "Dionysios of Fourna, Hermeneia §17, 19 (tr. Parpulov, Dolgikh and Cowe, Dumbarton Oaks Papers 64, 2010)",
               link: "https://www.pallasweb.com/deesis/byzantine-text-technique-of-icon-painting.html"),
        Credit(name: "Cinnabaris", hex: 0xBE3322, kind: .pigment,
               what: "Cinnabar (mercury sulphide) from Sisapo in Spain, refined at Rome; used by the ancients for monochrome pictures",
               citation: "Pliny, Natural History 33.39-40",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=39"),
        Credit(name: "Red Lead", hex: 0xDC4A2C, kind: .pigment,
               what: "Lead white roasted in a furnace; with beeswax, the red of Herakleides' and seven other mummy shrouds, imported from Spain",
               citation: "Vitruvius, De architectura 7.12.2 (tr. Gwilt); Getty Museum, Investigating Herakleides (Google Arts & Culture)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Sandarach", hex: 0xF07A2E, kind: .pigment,
               what: "Red arsenic sulphide (realgar) or a spurious kind from burnt ceruse; 'ought to be of a flame color'",
               citation: "Pliny, Natural History 35.22, 34.55",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=22"),
        Credit(name: "Orpiment", hex: 0xE8B533, kind: .pigment,
               what: "Yellow arsenic sulphide (Greek arsenikon), best from Pontus; much used by painters",
               citation: "Vitruvius, De architectura 7.7.5 (tr. Gwilt); Pliny, Natural History 33.22",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Sil", hex: 0xC0913F, kind: .pigment,
               what: "Yellow ochre found in gold and silver mines; Attic, marbled, Scyric, Achaian, Gallic kinds",
               citation: "Pliny, Natural History 33.56",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=56"),
        Credit(name: "Attic Sil", hex: 0xD8AD5C, kind: .pigment,
               what: "The best sil, used by Polygnotus and Micon and later for strong lights; Apelles' yellow",
               citation: "Pliny, Natural History 33.56, 35.32",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=56"),
        Credit(name: "Scyric Sil", hex: 0x8D6A3C, kind: .pigment,
               what: "Compressed sil from Scyros, used with the Lydian kind for shadow painting",
               citation: "Pliny, Natural History 33.56",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=56"),
        Credit(name: "Yellow Ochre", hex: 0xC8A24C, kind: .pigment,
               what: "Hydrated iron-oxide earth; on the yellow beads and background of a Fayum portrait",
               citation: "ColourLex; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017)",
               link: "https://colourlex.com/project/yellow-ochre/"),
        Credit(name: "Attic Ochre", hex: 0xE7C387, kind: .pigment,
               what: "Native ochre (Greek ochra) dug in the Attic silver mines, no longer to be had in Vitruvius' time",
               citation: "Vitruvius, De architectura 7.7.1 (tr. Gwilt)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Orange Ochre", hex: 0xC9833F, kind: .pigment,
               what: "Orange iron-oxide earth, used since prehistoric times",
               citation: "ColourLex",
               link: "https://colourlex.com/project/orange-ochre/"),
        Credit(name: "Goethite", hex: 0xA27940, kind: .pigment,
               what: "Iron oxide-hydroxide, the yellow-brown iron earth in Tebtunis and Fayum portraits",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; Delaney et al., Scientific Reports 7 (2017)",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Jarosite", hex: 0xC2AA62, kind: .pigment,
               what: "Pale yellow iron sulphate mineral among the iron earths of Tebtunis and Fayum portraits",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; Delaney et al., Scientific Reports 7 (2017)",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Quaestorian Leaf", hex: 0xC49A4C, kind: .pigment,
               what: "The second-thickest grade of Roman gold leaf, after the 'leaf of Praeneste'",
               citation: "Pliny, Natural History 33.19",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=19"),
        Credit(name: "Beeswax", hex: 0xCDA557, kind: .pigment,
               what: "Binder of Fayum encaustic and of the red-lead shrouds; the best yellow wax came from Pontus",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; Pliny, Natural History 21.49",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Punic Wax", hex: 0xE9DFC4, kind: .pigment,
               what: "Yellow wax bleached in the open air and boiled with sea water and nitre; rubbed hot on vermilion walls",
               citation: "Pliny, Natural History 21.49; Vitruvius, De architectura 7.9.3 (tr. Gwilt)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=21:chapter=49"),
        Credit(name: "Lead White", hex: 0xF2EEE4, kind: .pigment,
               what: "Basic lead carbonate made with lead and vinegar; in the flesh tones of Fayum portraits",
               citation: "ColourLex; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017)",
               link: "https://colourlex.com/project/lead-white/"),
        Credit(name: "Melinum", hex: 0xE8E2D3, kind: .pigment,
               what: "White earth from Melos; Apelles' white",
               citation: "Pliny, Natural History 35.19, 35.32",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=19"),
        Credit(name: "Paraetonium", hex: 0xF3F1EA, kind: .pigment,
               what: "White from Paraetonium in Egypt, said to be sea-foam with slime; the most unctuous white",
               citation: "Pliny, Natural History 35.18",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=18"),
        Credit(name: "Chalk", hex: 0xEEEDE7, kind: .pigment,
               what: "Calcium carbonate, used with madder lake on the tunic of a Fayum portrait and as a base for purpurissum",
               citation: "ColourLex, calcite; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017)",
               link: "https://colourlex.com/project/calcite/"),
        Credit(name: "Gypsum", hex: 0xF4F2EC, kind: .pigment,
               what: "Calcium sulphate; white ground for panels and the sketches on Tebtunis portraits",
               citation: "Getty APPEAR project: the Tebtunis portraits at the Hearst Museum; Theophilus, De diversis artibus 1.19 (tr. Hendrie, 1847)",
               link: "https://www.getty.edu/publications/mummyportraits/part-two/14/"),
        Credit(name: "Cimolian Earth", hex: 0xD6D0C8, kind: .pigment,
               what: "Cretaceous earth used in medicine and for scouring cloth; one kind white, one tinged like purpurissum",
               citation: "Pliny, Natural History 35.57",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=57"),
        Credit(name: "Argentaria", hex: 0xE5E3DE, kind: .pigment,
               what: "'Silver chalk', named for the brightness it gives silver; dyed with purple to make purpurissum",
               citation: "Pliny, Natural History 35.58, 35.26",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=58"),
        Credit(name: "Green Earth", hex: 0x7E8466, kind: .pigment,
               what: "Greyish green clay earth, in use from antiquity; base of Byzantine flesh undercoats",
               citation: "ColourLex",
               link: "https://colourlex.com/project/green-earth/"),
        Credit(name: "Theodotion", hex: 0x8A9272, kind: .pigment,
               what: "Green chalk; the best from Smyrna, named after Theodotus, on whose land it was found",
               citation: "Vitruvius, De architectura 7.7.2 (tr. Gwilt)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Appianum", hex: 0x8FA078, kind: .pigment,
               what: "Cheap green made from a green chalk, imitating chrysocolla",
               citation: "Pliny, Natural History 35.29",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=29"),
        Credit(name: "Chrysocolla", hex: 0x6F9A3E, kind: .pigment,
               what: "Copper green found in mines, dyed with the plant lutum; best when it has 'the tint of corn when in a state of the freshest verdure'",
               citation: "Pliny, Natural History 33.26-27; Vitruvius, De architectura 7.9.6 (tr. Gwilt)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=26"),
        Credit(name: "Verdigris", hex: 0x3E8F7E, kind: .pigment,
               what: "Copper acetate made by hanging copper over vinegar; in the green beads of a Fayum portrait (in beeswax)",
               citation: "Pliny, Natural History 34.26; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017); ColourLex",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=34:chapter=26"),
        Credit(name: "Malachite", hex: 0x2E8B5A, kind: .pigment,
               what: "Green copper carbonate mineral, used in ancient Egypt",
               citation: "ColourLex",
               link: "https://colourlex.com/project/malachite/"),
        Credit(name: "Egyptian Blue", hex: 0x2468A8, kind: .pigment,
               what: "Synthetic copper calcium silicate made from sand, natron and copper; in Fayum portrait backgrounds",
               citation: "Vitruvius, De architectura 7.11.1 (tr. Gwilt); ColourLex; Getty APPEAR project: the Tebtunis portraits at the Hearst Museum",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Caeruleum", hex: 0x2E86B0, kind: .pigment,
               what: "Roman blue 'sand': Egyptian, Scythian, Cyprian, later Puteoli and Spain; laid on clay, not lime",
               citation: "Pliny, Natural History 33.57",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=57"),
        Credit(name: "Lomentum", hex: 0x74BCD8, kind: .pigment,
               what: "Caeruleum washed and ground, 'of a paler tint than caeruleum'",
               citation: "Pliny, Natural History 33.57",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=57"),
        Credit(name: "Armenium", hex: 0x5B8FC4, kind: .pigment,
               what: "Blue mineral from Armenia (azurite), like caeruleum but whiter",
               citation: "Pliny, Natural History 35.28; ColourLex, azurite",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=28"),
        Credit(name: "Azurite", hex: 0x1F4C98, kind: .pigment,
               what: "Blue copper carbonate mineral, in use since antiquity",
               citation: "ColourLex",
               link: "https://colourlex.com/project/azurite/"),
        Credit(name: "Indicum", hex: 0x18223F, kind: .pigment,
               what: "Indigo from India: black as a powder, purple and blue when diluted; used in Tebtunis portraits",
               citation: "Pliny, Natural History 35.27; Getty APPEAR project: the Tebtunis portraits at the Hearst Museum",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=27"),
        Credit(name: "Purpurissum", hex: 0xA2567E, kind: .pigment,
               what: "Silver chalk dyed with purple in the dyer's cauldron; best from Puteoli",
               citation: "Pliny, Natural History 35.26",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=35:chapter=26"),
        Credit(name: "Ostrum", hex: 0x6A2450, kind: .pigment,
               what: "Purple from the marine shell, prepared with honey; varies from brown to violet to red by region",
               citation: "Vitruvius, De architectura 7.13 (tr. Gwilt)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Tyrian Purple", hex: 0x4A2148, kind: .pigment,
               what: "Shellfish purple; best 'of the color of clotted blood ... blackish to the sight'",
               citation: "Pliny, Natural History 9.62; ColourLex",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=9:chapter=62"),
        Credit(name: "Vaccinium", hex: 0x6C4A7C, kind: .pigment,
               what: "A purple made from vaccinium mixed with milk, a cheap 'factitious' color",
               citation: "Vitruvius, De architectura 7.14.2 (tr. Gwilt)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Madder Lake", hex: 0xC24F6A, kind: .pigment,
               what: "Madder dye on a mineral base; in the red-purple tunic of a Fayum portrait and the pinks of Tebtunis portraits",
               citation: "ColourLex; ColourLex: a Fayum portrait of a woman (National Gallery of Art), after Delaney et al., Scientific Reports 7 (2017); Getty APPEAR project: the Tebtunis portraits at the Hearst Museum",
               link: "https://colourlex.com/project/madder-lake/"),
        Credit(name: "Gold Tessera", hex: 0xE4BD59, kind: .glass,
               what: "Glass tessera with gold leaf under 0.5 µm sealed between a glass support and a thin glass top layer.",
               citation: "Guerra, Neri and Radtke, “Gold leaf tesserae”, The European Physical Journal Plus 138 (2023)",
               link: "https://flore.unifi.it/retrieve/083b1696-9046-409a-b5ea-9e1d5c9f9389/GuerraNeriRadtke_EurPhysJPlus_2023.pdf"),
        Credit(name: "Gold Leaf", hex: 0xDBAC36, kind: .glass,
               what: "Gold leaf laid on one side of glass squares and covered with ground clear glass to make mosaic glass.",
               citation: "Theophilus, De diversis artibus 2.15 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Greek Glass", hex: 0xD1982B, kind: .glass,
               what: "Theophilus's name for the gold-leaf glass squares that ornament mosaic work.",
               citation: "Theophilus, De diversis artibus 2.15 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Electrum", hex: 0xCBAA7C, kind: .glass,
               what: "Natural or artificial alloy of gold with about a fifth silver.",
               citation: "Pliny, Natural History 33.23",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=33:chapter=23"),
        Credit(name: "Silver Tessera", hex: 0xE0D4C5, kind: .glass,
               what: "Glass tessera with silver leaf, used with gold to set off other colors.",
               citation: "Guerra, Neri and Radtke, “Gold leaf tesserae”, The European Physical Journal Plus 138 (2023)",
               link: "https://flore.unifi.it/retrieve/083b1696-9046-409a-b5ea-9e1d5c9f9389/GuerraNeriRadtke_EurPhysJPlus_2023.pdf"),
        Credit(name: "Silver Leaf", hex: 0xC4B8A4, kind: .glass,
               what: "Silver leaf in a 9th-century tessera from Sant'Apollinare Nuovo, Ravenna, with a green glass support and a yellow cover glass.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Cartellina", hex: 0xC2C2B3, kind: .glass,
               what: "The thin glass layer over the metal leaf of a gold or silver tessera; usually transparent and colorless.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Stannum", hex: 0x8E8386, kind: .glass,
               what: "Pliny's stannum (tin-lead) used to coat copper vessels so they looked like silver.",
               citation: "Pliny, Natural History 34.48",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=34:chapter=48"),
        Credit(name: "Smalti", hex: 0x1A827D, kind: .glass,
               what: "Colored glass paste cut into tesserae for wall mosaics.",
               citation: "Mosaic Matters glossary, after M. Farneti, Glossario tecnico-storico del mosaico (1993)",
               link: "https://www.mosaicmatters.co.uk/glossary.htm"),
        Credit(name: "Sapphire Glass", hex: 0x41466E, kind: .glass,
               what: "Theophilus's 'sapphire' (blue) opaque glass found in ancient mosaic work.",
               citation: "Theophilus, De diversis artibus 2.12 (tr. Hendrie, 1847)",
               link: "https://archive.org/details/theophiliquietru00theouoft"),
        Credit(name: "Cobalt Glass", hex: 0x041B56, kind: .glass,
               what: "Blue glass colored with cobalt, found in Ravenna's mosaic tesserae (Neonian Baptistery and others).",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Obsian Glass", hex: 0x282828, kind: .glass,
               what: "Pliny's artificial 'Obsian stone' of colored glass, imitating very dark obsidian.",
               citation: "Pliny, Natural History 36.67",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=67"),
        Credit(name: "Black Paste", hex: 0x1C1A1F, kind: .glass,
               what: "Opaque black glass paste, as catalogued for a Roman ring stone.",
               citation: "The Met, Opaque black glass ring stone with a white band, Roman, 1st-3rd c. (17.194.56)",
               link: "https://www.metmuseum.org/art/collection/search/249301"),
        Credit(name: "Blue Paste", hex: 0x4B6174, kind: .glass,
               what: "Opaque blue glass paste, as catalogued for a Roman engraved gem.",
               citation: "The Met, Opaque blue glass oval engraved gem, Roman, 1st c. BCE (17.194.37)",
               link: "https://www.metmuseum.org/art/collection/search/249282"),
        Credit(name: "Amber Glass", hex: 0x8C6810, kind: .glass,
               what: "Translucent natron glass colored amber by an iron-sulphur chromophore, Hellenistic to early Roman.",
               citation: "Paynter and Jackson, “Mellow yellow: an experiment in amber”, Journal of Archaeological Science: Reports 22 (2018)",
               link: "https://eprints.whiterose.ac.uk/id/eprint/125338/1/1-s2.0-S2352409X17305084-main.pdf"),
        Credit(name: "Natron Glass", hex: 0xA7BEBD, kind: .glass,
               what: "Soda glass fluxed with natron; most Roman glass is transparent light blue or green from impurities.",
               citation: "Paynter and Jackson, “Mellow yellow: an experiment in amber”, Journal of Archaeological Science: Reports 22 (2018); Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://eprints.whiterose.ac.uk/id/eprint/125338/1/1-s2.0-S2352409X17305084-main.pdf"),
        Credit(name: "Opaque Turquoise", hex: 0x1984A4, kind: .glass,
               what: "Opaque turquoise glass tessera colored with copper, opacified with calcium antimonate.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Opaque White", hex: 0xEEE8E0, kind: .glass,
               what: "White glass tesserae opacified with calcium antimonate or calcium phosphate (Neonian Baptistery, Ravenna).",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Copper Green", hex: 0x376643, kind: .glass,
               what: "Green glass tesserae colored with copper oxide (San Vitale presbytery set).",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Lead Antimonate", hex: 0xEDC053, kind: .glass,
               what: "Opacifier and colorant of opaque yellow glass up to the Roman period.",
               citation: "Di Bella et al., “Lead stannate as component of antique yellow glassy tesserae from Sicilian mosaics”, Mediterranean Archaeology and Archaeometry (2022)",
               link: "https://www.earth-prints.org/bitstream/2122/16231/1/Di_Bella_et_al_22%283%29.pdf"),
        Credit(name: "Lead Stannate", hex: 0xE1BC33, kind: .glass,
               what: "Lead-tin yellow opacifier that replaced lead antimonate in yellow glass from about the 4th century AD.",
               citation: "Di Bella et al., “Lead stannate as component of antique yellow glassy tesserae from Sicilian mosaics”, Mediterranean Archaeology and Archaeometry (2022)",
               link: "https://www.earth-prints.org/bitstream/2122/16231/1/Di_Bella_et_al_22%283%29.pdf"),
        Credit(name: "Orange Tessera", hex: 0xD8980C, kind: .glass,
               what: "Opaque orange glass tessera, lead- and tin-rich, from Ravenna's Neonian Baptistery.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Haematinum", hex: 0x963528, kind: .glass,
               what: "Pliny's opaque glass, red all through.",
               citation: "Pliny, Natural History 36.67",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=67"),
        Credit(name: "Cuprite", hex: 0xC14231, kind: .glass,
               what: "Copper(I) oxide in opaque red glass; with copper nanoparticles it gave a Ravenna red tessera its color.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Sealing-wax Red", hex: 0xBC4437, kind: .glass,
               what: "High-lead opaque red glass colored by Cu2O crystals; it went out of use around the 1st century CE.",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Manganese", hex: 0x6B5756, kind: .glass,
               what: "Manganese oxide colored purple and black-purple tesserae (Ravenna, San Vitale).",
               citation: "Fiorentino, Chinni and Vandini, “Ravenna, its mosaics and the contribution of archaeometry”, Journal of Cultural Heritage 46 (2020)",
               link: "https://cris.unibo.it/retrieve/6c7bd1e1-6774-4a72-bcc4-74ff4e5d4dee/CULHER_3792_edit_report%20.pdf"),
        Credit(name: "Terracotta", hex: 0xAA3F1B, kind: .glass,
               what: "Fired clay; ceramic is one of the materials cut into tesserae.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 3",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Cocciopesto", hex: 0x815C46, kind: .glass,
               what: "Pavement of lime mortar mixed with ceramic or stone fragments.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 18",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Opus Signinum", hex: 0xA36E61, kind: .glass,
               what: "Lime mortar with ceramic fragments, set with tesserae or stone fragments.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 16",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Opus Figlinum", hex: 0xAF8A81, kind: .glass,
               what: "Pavement of rectangular ceramic pieces set on edge in a basket-weave pattern.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 14",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Opus Spicatum", hex: 0x7C7C6E, kind: .glass,
               what: "Pavement of rectangular ceramic elements in a herringbone pattern.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 15",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Lime Mortar", hex: 0xA8A994, kind: .glass,
               what: "Mortar of lime and aggregate; the bedding layer that holds the tesserae is very rich in lime.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 2",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Mortar Pavement", hex: 0x98917E, kind: .glass,
               what: "Pavement of lime mortar with stone fragments, without inserted tesserae.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 18",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Pebble", hex: 0x74726C, kind: .glass,
               what: "Natural pebbles set on edge to make figures or geometric motifs.",
               citation: "Getty Conservation Institute and INP, Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics (2013), p. 10",
               link: "https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf"),
        Credit(name: "Faience", hex: 0x3DD1E4, kind: .glass,
               what: "Egyptian faience, a glazed non-clay ceramic, blue-green.",
               citation: "The Met, Hippopotamus ('William'), Egypt (17.9.1)",
               link: "https://www.metmuseum.org/art/collection/search/544227"),
        Credit(name: "Cloisonne Enamel", hex: 0x485474, kind: .glass,
               what: "Glass enamel fused into gold cloisons, Byzantine c. 1100.",
               citation: "The Met, Medallion with Christ from an Icon Frame, Byzantine, ca. 1100 (17.190.678)",
               link: "https://www.metmuseum.org/art/collection/search/464551"),
        Credit(name: "Limewood", hex: 0xA87D40, kind: .glass,
               what: "Wooden panel for Roman-Egyptian (Fayum) encaustic portraits.",
               citation: "The Met, Portrait of a thin-faced, bearded man, 160-180 CE (09.181.1)",
               link: "https://www.metmuseum.org/art/collection/search/547856"),
        Credit(name: "Linen", hex: 0xB3A27C, kind: .glass,
               what: "Linen wrappings of a Roman-period Egyptian mummy with an inserted panel portrait.",
               citation: "The Met, Mummy with an Inserted Panel Portrait of a Youth, 80-100 CE (11.139)",
               link: "https://www.metmuseum.org/art/collection/search/547697"),
        Credit(name: "Shell", hex: 0xCEAF85, kind: .glass,
               what: "Mother-of-pearl shell; listed among the materials of San Vitale's Theodora mosaic.",
               citation: "BYZART, University of Bologna: San Vitale, Ravenna, Theodora and her retinue",
               link: "https://historica.unibo.it/handle/20.500.14008/441"),
        Credit(name: "Topazos", hex: 0x98A152, kind: .stone,
               what: "Pliny's topazos, a gem \"held in very high estimation for its green tints\"; identified today as peridot (gem olivine), yellow-green.",
               citation: "Pliny, Natural History 37.32; GIA, Peridot from Egypt; The Met, peridot ring stone (244991)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=32"),
        Credit(name: "Pyrochlore", hex: 0xADBD6C, kind: .glass,
               what: "Opaque yellow-green mosaic glass: yellow crystals of lead antimonate (pyrochlore, the modern mineral name) dispersed in colorless or green glass, among the most abundant yellow and green tesserae of late Roman and Byzantine mosaics.",
               citation: "Neri, Morvan, Colomban, Guerra and Prigent, “Late Roman and Byzantine mosaic opaque glass-ceramics tesserae (5th–9th century)”, Ceramics International 42 (2016), fig. 1",
               link: "https://hal.sorbonne-universite.fr/hal-01375484/document"),
        Credit(name: "Green Tessera", hex: 0x56703C, kind: .glass,
               what: "Opaque leaf-green glass tessera, Byzantine (The Met's tesserae set, not analysed); greens of this kind were made by dispersing yellow lead antimonate in blue or green glass.",
               citation: "The Met, Mosaic Tesserae, Byzantine (2016.11.1–.50); Neri, Morvan, Colomban, Guerra and Prigent, “Late Roman and Byzantine mosaic opaque glass-ceramics tesserae (5th–9th century)”, Ceramics International 42 (2016)",
               link: "https://www.metmuseum.org/art/collection/search/708074"),
        Credit(name: "Luteum", hex: 0xE6D23C, kind: .pigment,
               what: "Weld (Reseda luteola), \"the herb called luteum\": a yellow dye the Romans knew, also laid over blue to make green.",
               citation: "Vitruvius, De architectura 7.14.2; Nuruosmaniye natural-dye database, weld",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Weld Green", hex: 0x296E29, kind: .pigment,
               what: "Vitruvius' cheap substitute for chrysocolla green: caeruleum (Egyptian blue) dyed over with weld, \"the most vivid green\".",
               citation: "Vitruvius, De architectura 7.14.2 (tr. Gwilt)",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Crocus", hex: 0xF0BE3A, kind: .pigment,
               what: "Saffron (Crocus sativus), held in high esteem since the Trojan War (Pliny); Theophilus colors with \"saffron, with which silk is colored\".",
               citation: "Pliny, Natural History 21.17; Theophilus, De diversis artibus 1.32 (tr. Hendrie, 1847); Nuruosmaniye natural-dye database, saffron",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=21:chapter=17"),
        Credit(name: "Carbunculus", hex: 0x4A191A, kind: .stone,
               what: "Pliny's carbunculus, the red gem named for its likeness to fire, of which the Alabandic kind was cut at Alabanda; usually identified as garnet, the garnet of late antique cloisonné.",
               citation: "Pliny, Natural History 37.25; The Met, ring with garnet, Roman (243672); The Met, cloisonné strap mount with garnets (468366)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=25"),
        Credit(name: "Coccum", hex: 0xA8202E, kind: .pigment,
               what: "Kermes (coccum, the \"scarlet berry\" of the holm oak, Kermes vermilio): the grain dye of Roman generals' cloaks.",
               citation: "Pliny, Natural History 16.12, 21.22, 22.3; Nuruosmaniye natural-dye database, Mediterranean kermes",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=16:chapter=12"),
        Credit(name: "Hysginum", hex: 0x7A1C32, kind: .pigment,
               what: "Hysginum: cloth first dyed with kermes, then steeped in Tyrian purple; Vitruvius also dyes chalk with it to make purple paint.",
               citation: "Pliny, Natural History 9.65, 35.26; Vitruvius, De architectura 7.14.1 (tr. Gwilt)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=9:chapter=65"),
        Credit(name: "Curalium", hex: 0xE17E4A, kind: .stone,
               what: "Red coral (Corallium rubrum), Pliny's curalium, prized from the Stoechades and Sicily; its color is read from Coptic beads of the 4th–7th c. taken to be coral.",
               citation: "Pliny, Natural History 32.11; The Met, Coptic beads (479605)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=32:chapter=11"),
        Credit(name: "Glastum", hex: 0x58758A, kind: .pigment,
               what: "Woad (Isatis tinctoria), Pliny's Gaulish glastum: the European indigo-blue dye; a light woad dye on wool is a greyish slate blue.",
               citation: "Pliny, Natural History 22.2; BioColour Library, woad on wool",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=22:chapter=2"),
        Credit(name: "Vitrum", hex: 0x24343F, kind: .pigment,
               what: "Vitrum, the Latin name of woad (Greek isatis): the Britons' blue body dye in Caesar, and Vitruvius' dye for chalk to imitate indigo; a deep woad on wool.",
               citation: "Vitruvius, De architectura 7.14.2; Caesar, Gallic War 5.14",
               link: "https://penelope.uchicago.edu/Thayer/E/Roman/Texts/Vitruvius/7*.html"),
        Credit(name: "Beryl", hex: 0x7B949A, kind: .stone,
               what: "Beryl (aquamarine), which Pliny ranks best when it has \"the pure green of the sea\"; a Severan beryl intaglio.",
               citation: "Pliny, Natural History 37.20; The Met, beryl intaglio of Julia Domna (251870)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=20"),
        Credit(name: "Callaina", hex: 0xB7BDA8, kind: .stone,
               what: "Pliny's callaina, a pale green stone \"easily counterfeited in glass\" (usually read as variscite/turquoise, callais); pale variscite beads on a Roman necklace.",
               citation: "Pliny, Natural History 37.33; The Met, necklace with variscite beads (250988)",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=37:chapter=33"),
        Credit(name: "Conchyliatum", hex: 0x8A5C78, kind: .pigment,
               what: "The \"conchyliated\" shellfish purple: the pale, highly esteemed tint, \"the clearer it is, the less of it the wool has imbibed\", shading through heliotrope and mallow.",
               citation: "Pliny, Natural History 9.64, 21.22",
               link: "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=9:chapter=64"),
    ]
}
