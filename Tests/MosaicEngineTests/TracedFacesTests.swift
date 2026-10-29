import Foundation
import Testing
import MosaicKit
@testable import MosaicEngine

/// A library picture's faces as the bench traced them for its bundled mosaics
/// (App/Ravenna/Resources/Mosaics/<id>-faces.json, written by sketchbook/bundle.py), which the app
/// lays the picture with once no bundled mosaic stands for its recipe (`MosaicMaker.tracedFaces`):
/// a line drawn in Refine, another count or a panel keeps the eyes.
@Suite("Traced faces")
struct TracedFacesTests {
    typealias Face = MosaicEngine.Face

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let mosaics = root.appendingPathComponent("App/Ravenna/Resources/Mosaics")
    static let fixture = root.appendingPathComponent("Tests/Fixtures/determinism")

    /// A faces file: the Standard picture's size and its faces, in its pixels.
    struct Traced: Decodable {
        var size: [Float]
        var faces: [Face]
    }

    struct Catalog: Decodable {
        struct Entry: Decodable { var id: String }
        var mosaics: [Entry]
    }

    static func traced(_ id: String) throws -> Traced {
        try JSONDecoder().decode(Traced.self, from: Data(contentsOf: mosaics.appendingPathComponent("\(id)-faces.json")))
    }

    @Test func eachWorkHasTheFacesItsMosaicsWereLaidWith() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.mosaics.appendingPathComponent("catalog.json")))
        #expect(catalog.mosaics.count == 9)
        for entry in catalog.mosaics {
            let traced = try Self.traced(entry.id)
            let standard = try JSONDecoder().decode(
                Mosaic.self, from: Data(contentsOf: Self.mosaics.appendingPathComponent("\(entry.id)-standard.json")))
            #expect(traced.size == [standard.width, standard.height], "\(entry.id): the Standard picture's pixels")
            let irises = standard.tiles.filter { $0.stage == .eye }.map(\.centre)
            // William the hippopotamus has no face; each portrait one, with both eyes.
            #expect(traced.faces.count == (entry.id == "william" ? 0 : 1), "\(entry.id)")
            for face in traced.faces {
                #expect(face.eyes.count == 2 && face.lines.contains { $0.kind == "eye" }, "\(entry.id)")
                for eye in face.eyes {
                    let nearest = irises.map { (($0 - SIMD2(eye[0], eye[1])) * ($0 - SIMD2(eye[0], eye[1]))).sum() }.min() ?? .infinity
                    #expect(nearest < 1, "\(entry.id): an eye its bundled mosaic has no iris at")
                }
            }
        }
    }

    @Test func aFaceIsCutToItsPanel() throws {
        let face = Face(box: [10, 20, 30, 40], eyes: [[15, 25, 2, 1]], lines: [.init(kind: "eye", pts: [[12, 24], [18, 26]])])
        let cut = try #require(face.cropped(scale: 2, origin: SIMD2(30, 30), width: 20, height: 100))
        #expect(cut.box == [0, 10, 20, 50])
        #expect(cut.eyes == [[0, 20, 4, 2]])
        #expect(cut.lines == [.init(kind: "eye", pts: [[-6, 18], [6, 22]])])
        // A face its panel leaves out is none of the panel's.
        #expect(face.cropped(scale: 1, origin: SIMD2(30, 0), width: 50, height: 50) == nil)
        #expect(face.cropped(scale: 1, origin: .zero, width: 10, height: 50) == nil)
        #expect(face.cropped(scale: 1, origin: .zero, width: 100, height: 100) == face)
    }

    /// A binary PPM (P6) or PGM (P5) of the fixture, as 0...1 samples.
    static func netpbm(_ name: String) throws -> (width: Int, height: Int, samples: [Float]) {
        let bytes = [UInt8](try Data(contentsOf: fixture.appendingPathComponent(name)))
        var i = 0, fields: [String] = []
        let space: Set<UInt8> = [9, 10, 13, 32]
        while fields.count < 4 {
            while space.contains(bytes[i]) { i += 1 }
            var s = ""
            while !space.contains(bytes[i]) { s.append(Character(UnicodeScalar(bytes[i]))); i += 1 }
            fields.append(s)
        }
        i += 1
        return (Int(fields[1])!, Int(fields[2])!, bytes[i...].map { Float($0) / 255 })
    }

    /// The eyes' pieces the engine lays of Young Woman in Red at the Fewer count (the determinism
    /// fixture's photo and contours, 403 × 724), rows `top` to `top + rows` of it, with `faces`.
    static func eyePieces(faces: [Face], top: Int = 0, rows: Int? = nil) throws -> Int {
        let photo = try netpbm("photo.ppm"), contours = try netpbm("contours.pgm")
        let w = photo.width, h = rows ?? photo.height - top
        let rgb = (top..<(top + h)).flatMap { y in
            (0..<w).map { x in let i = (y * w + x) * 3; return SIMD3(photo.samples[i], photo.samples[i + 1], photo.samples[i + 2]) }
        }
        let map = Array(contours.samples[(top * w)..<((top + h) * w)])
        let mosaic = try MosaicEngine.make(photo: .init(width: w, height: h, rgb: rgb), contours: map, faces: faces)
        return mosaic.tiles.filter { $0.stage == .eye }.count
    }

    @Test func aLibraryPictureKeepsItsEyesWhenTheEngineLaysIt() throws {
        let traced = try Self.traced("young-woman-in-red")
        let photo = try Self.netpbm("photo.ppm")
        let k = Float(photo.width) / traced.size[0]
        // Its bundled mosaics' eyes: each an iris and its pupil.
        let whole = traced.faces.compactMap { $0.cropped(scale: k, origin: .zero, width: Float(photo.width), height: Float(photo.height)) }
        #expect(try Self.eyePieces(faces: whole) == 4)
        // A square panel round the face.
        let top = 52, side = photo.width
        let square = traced.faces.compactMap { $0.cropped(scale: k, origin: SIMD2(0, Float(top)), width: Float(side), height: Float(side)) }
        #expect(square.count == 1)
        #expect(try Self.eyePieces(faces: square, top: top, rows: side) == 4)
        // Without them, as the app laid it when Vision found no face: no eyes.
        #expect(try Self.eyePieces(faces: []) == 0)
    }
}
