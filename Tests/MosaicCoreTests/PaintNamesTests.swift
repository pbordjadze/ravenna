import Foundation
import MosaicKit
import PaintCore
import Testing
@testable import MosaicCore

/// Ravenna's paint names (`PaintNames`): a well-formed table that names most paints of the
/// library's mosaics.
@Suite("Paint names")
struct PaintNamesTests {
    /// The bundled mosaics' paints, the grout's last, as `MosaicCore.template(of:)` makes them.
    static func palettes() throws -> [String: [PaletteColor]] {
        let files = try FileManager.default.contentsOfDirectory(at: TemplateTests.mosaics, includingPropertiesForKeys: nil)
        var palettes: [String: [PaletteColor]] = [:]
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "catalog.json" {
            let mosaic = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: file))
            palettes[file.deletingPathExtension().lastPathComponent] = (mosaic.palette + [mosaic.grout]).map {
                PaletteColor(oklab: ColorScience.encodedToOKLab($0, space: .sRGB), rgb: $0)
            }
        }
        return palettes
    }

    @Test func theTableIsWellFormed() {
        let vocabulary = PaintNames.vocabulary
        #expect(vocabulary.formatProblems.isEmpty, "\(vocabulary.formatProblems)")
        // PaintCore's size and gamut checks ask a vocabulary to name every colour; Ravenna's names
        // only the materials there were, and the rest keep their structured names.
        let problems = vocabulary.problems().filter { !$0.hasPrefix("gamut:") && !$0.contains("entries: expected") }
        #expect(problems.isEmpty, "\(problems)")
        let names = vocabulary.entries.map(\.name)
        #expect(Set(names).count == names.count, "no name twice")
        #expect(vocabulary.entries.count == PaintNames.table.split(separator: "\n").count)
    }

    @Test func mostPaintsOfTheLibraryHaveNames() throws {
        let palettes = try Self.palettes()
        #expect(palettes.count >= 27)
        var named = 0, paints = 0, before = 0
        for (id, palette) in palettes.sorted(by: { $0.key < $1.key }) {
            for seed: UInt64 in 1...4 {
                let names = PaintNames.names(for: palette, seed: seed).compactMap { $0 }
                let old = ColorNickname.assign(palette, seed: seed, version: ColorNickname.currentVersion)
                named += names.count
                before += old.filter(ColorNickname.isNickname).count
                paints += palette.count
            }
        }
        print("Paint names: \(named) of \(paints) paints named over 4 seeds (Paint by Moonlight's vocabulary: \(before))")
        #expect(Double(named) >= 0.97 * Double(paints))
    }

    /// The table is frozen once shipped (its order takes part in the draw): an edit fails here, and
    /// is a new table with its own version instead.
    @Test func theTableIsFrozen() {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV-1a
        for byte in PaintNames.table.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        #expect(PaintNames.vocabulary.entries.count == 189)
        #expect(hash == 0xf5c8_5a2b_0226_c306, "FNV-1a \(String(hash, radix: 16))")
    }

    /// One library palette's names on Linux (v1's draw uses Float `exp`, so a device's may differ):
    /// a change to the table, the draw or PaintCore's colour maths moves them.
    @Test func aPaletteKeepsItsNames() throws {
        let palette = try #require(try Self.palettes()["hodegetria-standard"])
        let names = PaintNames.names(for: palette, seed: 1)
        #expect(names == [
            "Cocciopesto", "Porporina", "Obsidian", "Cottanello", "Rosso Antico", "Sinopis", "Goethite",
            "Syenites", "Ampelitis", "Agata", "Exudra", "Bigio Antico", "Porphyrites", "Bole", "Proplasmos",
            "Cicerculum", "Aventurine", "Burnt Umber", "Pudingo Antico", "Carbunculus", "Black Paste",
            "Charcoal Black", "Cimolian Earth",
        ], "\(names)")
    }

    /// The credits and the table are written from docs/paint-names.json (tools/paint_names.py): the
    /// Swift says what the JSON says, in its order, and every name has its citation.
    @Test func theCreditsAreTheJSONs() throws {
        struct Entry: Decodable { let name, hex, kind, what, citation: String; let link: String? }
        let url = TemplateTests.mosaics.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/paint-names.json")
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        let credits = PaintNames.credits
        #expect(entries.count == credits.count)
        #expect(credits.map(\.name) == PaintNames.vocabulary.entries.map(\.name))
        #expect(credits.map(\.hex) == PaintNames.vocabulary.entries.map(\.hex))
        for (entry, credit) in zip(entries, credits) {
            #expect(entry.name == credit.name && UInt32(entry.hex, radix: 16) == credit.hex && entry.kind == credit.kind.rawValue
                && entry.what == credit.what && entry.citation == credit.citation && entry.link == credit.link,
                "\(entry.name): run tools/paint_names.py")
            #expect(!credit.citation.isEmpty && !credit.what.isEmpty)
            if let link = credit.link { #expect(URL(string: link)?.scheme == "https", "\(credit.name): \(link)") }
        }
    }

    /// A paint no material comes within `PaintNames.maximumDistance` of keeps its plain name, though
    /// PaintCore's draw would reach farther: a vivid sky blue (#00A0FF, 0.093 from Armenium) and pure black have none.
    @Test func aFarPaintKeepsItsPlainName() {
        let palette = [SIMD3<Float>(0, 0.627, 1), SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.831, 0.69, 0.443)].map {
            PaletteColor(oklab: ColorScience.encodedToOKLab($0, space: .sRGB), rgb: $0)
        }
        let names = PaintNames.names(for: palette, seed: 1)
        #expect(names[0] == nil && names[1] == nil, "\(names)")
        #expect(names[2] != nil, "giallo antico's own colour is named")
        #expect(PaintNames.vocabulary.entries.map(\.name).contains(ColorNickname.assign(palette, seed: 1, vocabulary: PaintNames.vocabulary)[0]),
                "PaintCore's draw alone would stretch a name to the sky blue")
    }
}
