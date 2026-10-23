import Foundation
import PaintCore
import Testing
@testable import MosaicCore

/// The pin on PaintCore is real: MosaicCore builds a PaintCore template that passes its own
/// validation and survives PaintCore's binary format.
@Suite("Ground")
struct GroundTests {
    static let gold = SIMD4<UInt8>(196, 154, 62, 255)

    @Test func theGroundIsOneValidAreaOfThePhotosColor() throws {
        let photo = RGBAImage(width: 32, height: 24, fill: Self.gold)
        let t = try MosaicCore.ground(width: 64, height: 48, photo: photo)
        #expect(t.width == 64 && t.height == 48)
        #expect(t.regions.count == 1 && t.palette.count == 1)
        #expect(t.regions[0].area == 64 * 48)
        let report = t.validate()
        #expect(report.isValid, "\(report)")
        let gold = ColorScience.encodedToOKLab(
            SIMD3(Float(Self.gold.x), Float(Self.gold.y), Float(Self.gold.z)) / 255, space: .sRGB)
        #expect(ColorScience.distance(t.palette[0].oklab, gold) < 1e-3)
        #expect(try Template(encoded: t.encoded()) == t)
        #expect(MosaicCore.paintCorePipelineVersion == t.pipelineVersion)
    }
}
