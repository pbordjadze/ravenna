import Foundation
import MosaicEngine
import MosaicKit
import PaintCore
import Testing
@testable import MosaicCore

/// The same photo makes the same mosaic on every device: the engine and the template, run on a
/// public-domain portrait (Tests/Fixtures/determinism, its README says where it comes from), hash to
/// the values Linux gives. Run on a Mac (`swift test --filter Determinism`) it answers whether Apple
/// silicon lays the same tiles. A hash is printed per part, so a difference says where it starts.
///
/// When the engine or the template changes on purpose, the hashes change: update them here (the
/// failure prints the new ones) and remake the bundled mosaics (sketchbook/bundle.py).
@Suite("Determinism")
struct DeterminismTests {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/determinism")

    /// The hashes on Linux (x86_64, Swift 6.2), debug and release alike.
    static let expected: [String: String] = [
        "engine.palette": "e1f851cbcb66817f",
        "engine.tiles": "d0cc4fda6490412",
        "template.palette": "533d60fbe57da087",
        "template": "4ab3f57257d625ab",
    ]

    /// FNV-1a, 64 bits: the same everywhere, unlike `Hasher`, which is seeded per process.
    struct FNV {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func add<T: FixedWidthInteger>(_ v: T) {
            withUnsafeBytes(of: v.littleEndian) { for b in $0 { value = (value ^ UInt64(b)) &* 0x0000_0100_0000_01b3 } }
        }
        mutating func add(_ v: Float) { add(v.bitPattern) }
        mutating func add(_ v: SIMD2<Float>) { add(v.x); add(v.y) }
        mutating func add(_ v: SIMD3<Float>) { add(v.x); add(v.y); add(v.z) }
        mutating func add(_ d: Data) { for b in d { add(b) } }
        var hex: String { String(value, radix: 16) }
    }

    /// A binary PPM (P6) or PGM (P5) with 8-bit samples, as 0...1 floats.
    static func netpbm(_ name: String) throws -> (width: Int, height: Int, samples: [Float]) {
        let bytes = [UInt8](try Data(contentsOf: folder.appendingPathComponent(name)))
        var i = 0, fields: [String] = []
        while fields.count < 4 {
            while bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9 { i += 1 }
            var s = ""
            while !(bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9) { s.append(Character(UnicodeScalar(bytes[i]))); i += 1 }
            fields.append(s)
        }
        i += 1
        let channels = fields[0] == "P6" ? 3 : 1, w = Int(fields[1])!, h = Int(fields[2])!
        #expect(fields[3] == "255" && bytes.count - i == w * h * channels, "\(name): an 8-bit binary PNM")
        return (w, h, bytes[i...].map { Float($0) / 255 })
    }

    @Test func aPortraitHashesAsOnLinux() throws {
        let photo = try Self.netpbm("photo.ppm"), contours = try Self.netpbm("contours.pgm")
        #expect(contours.width == photo.width && contours.height == photo.height)
        let face = try JSONDecoder().decode(MosaicEngine.Face.self, from: Data(contentsOf: Self.folder.appendingPathComponent("features.json")))
        let s = photo.samples
        let rgb = (0..<(photo.width * photo.height)).map { SIMD3(s[3 * $0], s[3 * $0 + 1], s[3 * $0 + 2]) }
        let mosaic = try MosaicEngine.make(photo: .init(width: photo.width, height: photo.height, rgb: rgb),
                                           contours: contours.samples, faces: [face])
        let template = try MosaicCore.template(of: mosaic)

        var hashes: [String: FNV] = [:]
        hashes["engine.palette", default: FNV()].add(mosaic.grout)
        for c in mosaic.palette { hashes["engine.palette", default: FNV()].add(c) }
        var tiles = FNV()
        tiles.add(mosaic.width); tiles.add(mosaic.height); tiles.add(mosaic.tiles.count)
        for t in mosaic.tiles {
            tiles.add(t.corners.count)
            for c in t.corners { tiles.add(c) }
            tiles.add(t.paint); tiles.add(t.stone ? 1 as UInt8 : 0)
            tiles.add(Data((t.stage?.rawValue ?? "").utf8))
        }
        hashes["engine.tiles"] = tiles
        for c in template.palette { hashes["template.palette", default: FNV()].add(c.oklab); hashes["template.palette"]!.add(c.rgb) }
        hashes["template", default: FNV()].add(template.encoded())

        let got = hashes.mapValues(\.hex)
        print("Determinism: \(mosaic.tiles.count) tiles, \(template.width) × \(template.height); "
              + got.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for (part, hex) in got.sorted(by: { $0.key < $1.key }) {
            #expect(hex == Self.expected[part], "\(part): \(hex), Linux gives \(Self.expected[part] ?? "nothing")")
        }
    }
}
