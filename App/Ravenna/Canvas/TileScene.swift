import CoreGraphics
import Foundation
import Metal
import MosaicEngine
import MosaicKit
import PaintCore

/// One region's tile, as the shaders draw it. Layout mirrors `TileShape` in Shaders.metal
/// (48 bytes: two float2, then 4-byte fields).
nonisolated struct TileShape {
    /// The tile's centre and the corner the light reaches first (template units).
    var centre: SIMD2<Float>
    var litCorner: SIMD2<Float>
    /// The side of a square of its bounds' area (template units).
    var size: Float
    /// Its corners in `TileScene.corners`.
    var cornerStart: UInt32
    var cornerCount: UInt32
    /// `TileShape.tile`, `.stone`, `.gold`, `.clockwise`; 0 for the grout.
    var flags: UInt32
    /// How far a raised tessera is turned (radians, at full lift).
    var turn: Float
    var pad0: Float = 0
    var pad1: Float = 0
    var pad2: Float = 0

    static let tile: UInt32 = 1
    static let stone: UInt32 = 2
    static let gold: UInt32 = 4
    static let clockwise: UInt32 = 8
}

/// The GPU side of a `TileWall`: per region its tile's shape and its body colour in each finish,
/// the tiles' corners, and the bed. Built once when a mosaic's canvas opens, beside its
/// `CanvasScene`. A scene that isn't a mosaic binds `TileScene.empty`'s placeholders, which no
/// shader reads (`CanvasUniforms.tiles.x` is 0).
nonisolated final class TileScene: @unchecked Sendable {
    let shapes: any MTLBuffer
    let corners: any MTLBuffer
    /// Linear P3 body colour per region (w unused), per finish (`TileColor.body`).
    private let bodies: [Finish: any MTLBuffer]
    /// The joints' colour when the grout is light (`Finish.flat`), linear P3.
    let grout: SIMD3<Float>

    func bodies(_ finish: Finish) -> any MTLBuffer { bodies[finish] ?? bodies[.flat]! }

    init?(wall: TileWall, device: any MTLDevice) {
        let m = wall.mosaic, k = wall.scale
        var shapes: [TileShape] = [], corners: [SIMD2<Float>] = []
        shapes.reserveCapacity(m.tiles.count + 1)
        for (i, t) in m.tiles.enumerated() {
            let c = t.corners.map { $0 * k }
            // The format and `TileWall` ensure corners; a tile without would have no shape.
            guard !c.isEmpty else { return nil }
            let (lo, hi) = t.bounds
            var flags = TileShape.tile
            if t.stone { flags |= TileShape.stone }
            if wall.gold[i] { flags |= TileShape.gold }
            if Light.clockwise(t.corners) { flags |= TileShape.clockwise }
            shapes.append(TileShape(
                centre: t.centre * k, litCorner: c[Light.litCorner(c)], size: ((hi.x - lo.x) * (hi.y - lo.y)).squareRoot() * k,
                cornerStart: UInt32(corners.count), cornerCount: UInt32(c.count), flags: flags,
                turn: 0.035 * TileColor.wobble(i, salt: 5)))
            corners += c
        }
        // The grout: no tile.
        shapes.append(TileShape(centre: .zero, litCorner: .zero, size: 0, cornerStart: 0, cornerCount: 0, flags: 0, turn: 0))
        grout = CanvasColor.linearP3(sRGB: m.grout)
        var bodies: [Finish: any MTLBuffer] = [:]
        for finish in Finish.allCases {
            let colors = m.tiles.indices.map { i in
                SIMD4(CanvasColor.linearP3(sRGB: TileColor.body(m.palette[m.tiles[i].paint], tile: i, finish: finish)), 0)
            } + [SIMD4(grout, 0)]
            guard let buffer = CanvasScene.buffer(colors, device) else { return nil }
            bodies[finish] = buffer
        }
        guard let shapeBuffer = CanvasScene.buffer(shapes, device), let cornerBuffer = CanvasScene.buffer(corners, device) else { return nil }
        self.shapes = shapeBuffer
        self.corners = cornerBuffer
        self.bodies = bodies
    }

    /// Placeholders for a scene that isn't a mosaic: every pass binds its buffers.
    private init?(device: any MTLDevice) {
        guard let empty = CanvasScene.buffer([UInt8](), device) else { return nil }
        shapes = empty
        corners = empty
        bodies = [.flat: empty]
        grout = .zero
    }

    static func empty(_ device: any MTLDevice) -> TileScene? { TileScene(device: device) }

    /// The painted bed under the tiles (`MosaicEngine.bed`: the tiles' colours blurred, darker
    /// and greyer, as the beds under Byzantine tesserae were painted), with a red-brown bole under
    /// a gold ground's tiles (`Mosaic.goldGround`) so their joints are warm, as v0's wall had.
    /// `longSide` pixels on the long side. Slow: call it off the main actor.
    static func bed(of wall: TileWall, longSide: Int = 1024) -> CGImage? {
        var m = wall.mosaic
        let scale = Float(longSide) / max(m.width, m.height)
        let w = max(Int((m.width * scale).rounded()), 1), h = max(Int((m.height * scale).rounded()), 1)
        for p in m.palette.indices where m.palette[p] == Mosaic.groundGold { m.palette[p] = SIMD3(0.6, 0.33, 0.2) }
        let pixels = MosaicEngine.bed(of: m, width: w, height: h)
        guard pixels.count == w * h else { return nil }
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for (i, c) in pixels.enumerated() {
            bytes[i * 4] = UInt8(min(max(c.x, 0), 1) * 255 + 0.5)
            bytes[i * 4 + 1] = UInt8(min(max(c.y, 0), 1) * 255 + 0.5)
            bytes[i * 4 + 2] = UInt8(min(max(c.z, 0), 1) * 255 + 0.5)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)
    }
}
