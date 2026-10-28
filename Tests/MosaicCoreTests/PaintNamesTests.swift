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
                #expect(Set(names).count == names.count, "\(id): unique within the palette")
                named += names.count
                before += old.filter(ColorNickname.isNickname).count
                paints += palette.count
            }
        }
        print("Paint names: \(named) of \(paints) paints named over 4 seeds (Paint by Moonlight's vocabulary: \(before))")
        #expect(Double(named) >= 0.9 * Double(paints))
    }
}
