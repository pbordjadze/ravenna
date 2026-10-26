import Foundation
import Metal
import PaintCore

/// Immutable GPU resources of one template: fill mesh, outline segments, number glyphs and
/// per-region colors. Built once when a canvas opens (a few flat copies — the template is
/// already laid out for upload) and shared by every frame and offscreen render.
///
/// The outline segments are `OutlineGeometry`'s: boundary edges, then for line art the strokes
/// inside cells, every line with its layer.
nonisolated final class CanvasScene: @unchecked Sendable {
    let canvasSize: SIMD2<Float>
    let regionCount: Int

    let positions: any MTLBuffer        // float2 per mesh vertex
    let vertexRegions: any MTLBuffer    // uint per mesh vertex
    let indices: any MTLBuffer          // uint32 triangle list
    let indexCount: Int

    let points: any MTLBuffer           // float2 boundary polyline points, then stroke points
    let segments: any MTLBuffer         // uint2 (first point, line) per segment
    let lineRegions: any MTLBuffer      // uint2 (left, right) per line (edge, then stroke)
    let lineLayers: any MTLBuffer       // float LineLayer per line (`OutlineGeometry.lightWritingMark` added for writing on dark paint)
    let segmentCount: Int
    /// Whether the template draws as a coloring book (`CanvasUniforms.setColoringBookLines`), not
    /// with classic lines (`setClassicLines`).
    let isColoringBook: Bool

    let glyphs: any MTLBuffer
    let glyphCount: Int
    let digitRects: any MTLBuffer
    let digitUVs: any MTLBuffer

    /// Linear P3 color per region; w = palette index.
    let regionColors: any MTLBuffer
    /// Linear P3 per palette color.
    let paletteLinear: [SIMD3<Float>]

    /// A mosaic's tiles (`TileWall`), drawn as tesserae on their ground; nil for paint.
    let tiles: TileScene?

    /// Font size (canvas units) of each region's primary number, 0 without one.
    let labelSizes: [Float]
    /// A small-but-typical number size (10th percentile), or a detail area's smallest when that
    /// is smaller (`Template.detailRegions`, read zoomed in): the max zoom makes these legible.
    let smallLabelSize: Float

    init?(template t: Template, context: RenderContext, wall: TileWall? = nil) {
        let device = context.device
        if let wall {
            guard let tiles = TileScene(wall: wall, device: device) else { return nil }
            self.tiles = tiles
        } else {
            tiles = nil
        }
        canvasSize = SIMD2(Float(t.width), Float(t.height))
        regionCount = t.regions.count

        let palette = t.palette.map { CanvasColor.linearP3($0, space: t.colorSpace) }
        paletteLinear = palette
        let colors = t.regions.map { SIMD4(palette[Int($0.colorIndex)], Float($0.colorIndex)) }
        let lines = OutlineGeometry(t)

        // Numbers: size each run by the shared `LabelSizing` rule (the same as thumbnails, PDFs
        // and SVG; a detail area's down to its own floor), capped so huge regions don't shout,
        // then emit one instance per digit placed with the atlas's real advances.
        let atlas = context.atlas
        let maxSize = LabelSizing.canvasMaximumFraction * Float(min(t.width, t.height))
        var glyphList: [GlyphInstance] = []
        glyphList.reserveCapacity(t.labels.count * 2)
        var sizes = [Float](repeating: 0, count: t.regions.count)
        var primary = [Bool](repeating: false, count: t.regions.count)
        for label in t.labels {
            let region = Int(label.region)
            let number = Int(t.regions[region].colorIndex) + 1
            let digits = String(number).compactMap(\.wholeNumberValue)
            let w = atlas.runWidth(digits)
            let size = LabelSizing.fontSize(
                radius: label.radius, digits: digits.count, maximum: maxSize, detail: t.isDetailRegion(region))
            if !primary[region] {
                primary[region] = true
                sizes[region] = size
            }
            var pen = -w / 2
            for d in digits {
                glyphList.append(GlyphInstance(center: label.position, size: size, offset: pen, digit: UInt32(d), region: label.region))
                pen += atlas.advances[d]
            }
        }
        labelSizes = sizes
        let sorted = sizes.filter { $0 > 0 }.sorted()
        let typical = sorted.isEmpty ? 1 : sorted[sorted.count / 10]
        let detail = t.detailRegions.compactMap { r in Int(r) < sizes.count && sizes[Int(r)] > 0 ? sizes[Int(r)] : nil }.min()
        smallLabelSize = min(typical, detail ?? typical)

        guard let positions = CanvasScene.buffer(t.mesh.vertices, device),
              let vertexRegions = CanvasScene.buffer(t.mesh.vertexRegion, device),
              let indices = CanvasScene.buffer(t.mesh.indices, device),
              let points = CanvasScene.buffer(lines.points, device),
              let segments = CanvasScene.buffer(lines.segments, device),
              let lineRegions = CanvasScene.buffer(lines.lineRegions, device),
              let lineLayers = CanvasScene.buffer(lines.lineLayers, device),
              let glyphs = CanvasScene.buffer(glyphList, device),
              let digitRects = CanvasScene.buffer(atlas.rects, device),
              let digitUVs = CanvasScene.buffer(atlas.uvs, device),
              let regionColors = CanvasScene.buffer(colors, device)
        else { return nil }
        self.positions = positions
        self.vertexRegions = vertexRegions
        self.indices = indices
        indexCount = t.mesh.indices.count
        self.points = points
        self.segments = segments
        self.lineRegions = lineRegions
        self.lineLayers = lineLayers
        segmentCount = lines.segments.count
        isColoringBook = lines.isColoringBook
        self.glyphs = glyphs
        glyphCount = glyphList.count
        self.digitRects = digitRects
        self.digitUVs = digitUVs
        self.regionColors = regionColors
    }

    /// A shared buffer holding `array`; 16 bytes when it is empty, since Metal makes no empty
    /// buffers and every pass binds its buffers.
    static func buffer<T>(_ array: [T], _ device: any MTLDevice) -> (any MTLBuffer)? {
        array.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else {
                return device.makeBuffer(length: 16, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }
}
