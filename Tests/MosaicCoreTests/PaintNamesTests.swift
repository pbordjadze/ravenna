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
        #expect(PaintNames.vocabulary.entries.count == 174)
        #expect(hash == 0x362d_5712_658d_e1cd, "FNV-1a \(String(hash, radix: 16))")
    }

    /// One library palette's names on Linux (v1's draw uses Float `exp`, so a device's may differ):
    /// a change to the table, the draw or PaintCore's colour maths moves them.
    @Test func aPaletteKeepsItsNames() throws {
        let palette = try #require(try Self.palettes()["hodegetria-standard"])
        let names = PaintNames.names(for: palette, seed: 1)
        #expect(names == [
            "Cocciopesto", "Porporina", "Obsidian", "Cottanello", "Rosso Antico", "Sinopis", "Goethite",
            "Syenites", "Ampelitis", "Agata", "Exudra", "Bigio Antico", "Porphyrites", "Bole", "Proplasmos",
            "Cicerculum", "Aventurine", "Burnt Umber", "Pudingo Antico", "Lydian Stone", "Black Paste",
            "Charcoal Black", "Cimolian Earth",
        ], "\(names)")
    }
}
