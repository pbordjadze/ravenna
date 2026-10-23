import Foundation
import Testing
@testable import MosaicKit

/// The app's bundled mosaics (App/Ravenna/Resources/Mosaics, made by sketchbook/bundle.py): each
/// decodes, has the tiles its catalog says, and carries every tile's stage for the making-of.
@Suite("Bundled mosaics")
struct BundledTests {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Ravenna/Resources/Mosaics")

    struct Catalog: Decodable {
        struct Entry: Decodable { var id: String; var tiles: [String: Int] }
        var mosaics: [Entry]
    }

    @Test func eachDecodesWithItsStages() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.folder.appendingPathComponent("catalog.json")))
        #expect(catalog.mosaics.count == 9)
        for entry in catalog.mosaics {
            for (detail, count) in entry.tiles {
                let file = Self.folder.appendingPathComponent("\(entry.id)-\(detail).json")
                let m = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: file))
                #expect(m.tiles.count == count, "\(entry.id)-\(detail)")
                #expect(m.tiles.allSatisfy { $0.stage != nil }, "\(entry.id)-\(detail): a tile without its stage")
            }
        }
    }
}
