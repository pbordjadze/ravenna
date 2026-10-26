import CoreGraphics
import Foundation
import Metal
import MosaicKit
import os
import PaintCore

/// Process-wide Metal state shared by every canvas and offscreen render: device, queue,
/// pipelines and the digit atlas. Immutable after creation, so it is safe to use from any
/// thread (the Metal objects it holds are thread-safe).
nonisolated final class RenderContext: @unchecked Sendable {
    static let shared: RenderContext? = RenderContext()

    /// Every canvas pass renders into this format; blending happens in linear light and the
    /// stored values are Display P3 with the sRGB curve.
    static let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    /// The outline coverage target: the ink's opacity (r) and the share of it in the light tone
    /// (g, writing over a dark paint).
    static let outlineFormat: MTLPixelFormat = .rg16Float

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let sampleCount: Int
    let atlas: DigitAtlas
    let atlasTexture: any MTLTexture

    let paperPipeline: any MTLRenderPipelineState
    let fillPipeline: any MTLRenderPipelineState
    let outlinePipeline: any MTLRenderPipelineState
    let compositePipeline: any MTLRenderPipelineState
    let glyphPipeline: any MTLRenderPipelineState
    let brushPipeline: any MTLRenderPipelineState
    let photoPipeline: any MTLRenderPipelineState
    let liftPipeline: any MTLRenderPipelineState
    /// What a scene that isn't a mosaic binds for the tile passes' buffers, which it never reads.
    let noTiles: TileScene

    /// Warms up the device, pipelines and atlas off the main thread so the first canvas
    /// opens instantly.
    static func prewarm() {
        Task.detached(priority: .userInitiated) { _ = RenderContext.shared }
    }

    /// `shared`, waited for off the caller's thread. Making it compiles the pipelines and waits on
    /// the GPU, which on a busy device (CI's simulator) has taken long enough that a canvas made
    /// on the main thread before then stopped the app answering; the painting screen awaits this
    /// before it shows one.
    @concurrent
    static func ready() async -> RenderContext? { shared }

    private init?() {
        let start = ContinuousClock.now
        defer { Log.canvas.notice("Making the render context took \(String(describing: ContinuousClock.now - start), privacy: .public)") }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: Bundle(for: RenderContext.self)),
              let atlas = DigitAtlas.make()
        else { return nil }
        self.device = device
        self.queue = queue
        self.atlas = atlas
        let samples = device.supportsTextureSampleCount(4) ? 4 : 1
        sampleCount = samples

        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat, samples: Int, blend: Blend) -> (any MTLRenderPipelineState)? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.rasterSampleCount = samples
            let c = d.colorAttachments[0]!
            c.pixelFormat = format
            switch blend {
            case .none:
                c.isBlendingEnabled = false
            case .premultiplied:
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .add
                c.alphaBlendOperation = .add
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case .max:
                c.isBlendingEnabled = true
                c.rgbBlendOperation = .max
                c.alphaBlendOperation = .max
                c.sourceRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .one
                c.destinationRGBBlendFactor = .one
                c.destinationAlphaBlendFactor = .one
            }
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        let n = samples, f = RenderContext.colorFormat
        guard let paper = pipeline("canvasRectVertex", "paperFragment", format: f, samples: n, blend: .premultiplied),
              let fill = pipeline("fillVertex", "fillFragment", format: f, samples: n, blend: .none),
              let outline = pipeline("outlineVertex", "outlineFragment", format: RenderContext.outlineFormat, samples: 1, blend: .max),
              let composite = pipeline("canvasRectVertex", "outlineCompositeFragment", format: f, samples: n, blend: .premultiplied),
              let glyph = pipeline("glyphVertex", "glyphFragment", format: f, samples: n, blend: .premultiplied),
              let brush = pipeline("brushVertex", "brushFragment", format: f, samples: n, blend: .premultiplied),
              let photo = pipeline("canvasRectVertex", "photoFragment", format: f, samples: n, blend: .premultiplied),
              let lift = pipeline("liftVertex", "liftFragment", format: f, samples: n, blend: .premultiplied),
              let noTiles = TileScene.empty(device),
              let texture = RenderContext.upload(atlas: atlas, device: device, queue: queue)
        else { return nil }
        paperPipeline = paper
        fillPipeline = fill
        outlinePipeline = outline
        compositePipeline = composite
        glyphPipeline = glyph
        brushPipeline = brush
        photoPipeline = photo
        liftPipeline = lift
        self.noTiles = noTiles
        atlasTexture = texture
    }

    nonisolated private enum Blend { case none, premultiplied, max }

    /// Private textures work on every GPU (including the simulator); upload via a blit.
    private static func upload(atlas: DigitAtlas, device: any MTLDevice, queue: any MTLCommandQueue) -> (any MTLTexture)? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: atlas.width, height: atlas.height, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .private
        let rowBytes = (atlas.width + 255) / 256 * 256
        var staged = [UInt8](repeating: 0, count: rowBytes * atlas.height)
        for y in 0..<atlas.height {
            for x in 0..<atlas.width { staged[y * rowBytes + x] = atlas.pixels[y * atlas.width + x] }
        }
        guard let texture = device.makeTexture(descriptor: desc),
              let buffer = device.makeBuffer(bytes: staged, length: staged.count, options: .storageModeShared),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: buffer, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: staged.count,
            sourceSize: MTLSize(width: atlas.width, height: atlas.height, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }

    /// The source photo as a mipmapped texture for the photo overlay. Drawn into Display P3
    /// with the sRGB curve, so sampling the `_srgb` texture yields linear P3 like every other
    /// canvas color; uploaded by blit into private storage. Waits for the GPU: call it off
    /// the main actor.
    func makePhotoTexture(_ image: CGImage) -> (any MTLTexture)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let rowBytes = (w * 4 + 255) / 256 * 256
        guard let staging = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let bitmap = CGContext(
                data: staging.contents(), width: w, height: h, bitsPerComponent: 8, bytesPerRow: rowBytes,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Row 0 in memory is the photo's top row, matching canvas +y down.
        bitmap.interpolationQuality = .high
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: true)
        desc.usage = .shaderRead
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        blit.copy(
            from: staging, sourceOffset: 0, sourceBytesPerRow: rowBytes, sourceBytesPerImage: rowBytes * h,
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return commands.status == .completed ? texture : nil
    }

    /// The finish a frame's tiles are drawn in (`CanvasUniforms.tiles.y`).
    private static func finish(of u: CanvasUniforms) -> Finish {
        switch Int(u.tiles.y.rounded()) {
        case 0: .flat
        case 1: .bed
        default: .material
        }
    }

    // MARK: Render targets

    func makeColorTarget(width: Int, height: Int) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// The multisampled color target; memoryless on device (it never leaves tile memory).
    func makeMultisampleTarget(width: Int, height: Int) -> (any MTLTexture)? {
        guard sampleCount > 1 else { return nil }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: width, height: height, mipmapped: false)
        d.textureType = .type2DMultisample
        d.sampleCount = sampleCount
        d.usage = .renderTarget
        #if targetEnvironment(simulator)
        d.storageMode = .private
        #else
        d.storageMode = .memoryless
        #endif
        return device.makeTexture(descriptor: d)
    }

    func makeOutlineTarget(width: Int, height: Int) -> (any MTLTexture)? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.outlineFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    // MARK: Encoding

    nonisolated struct Targets {
        /// Final color (drawable or offscreen texture).
        var color: any MTLTexture
        var multisample: (any MTLTexture)?
        var outlines: any MTLTexture
    }

    nonisolated struct Content {
        var outlines = true
        var numbers = true
        var brush = false
        /// Margin around the paper for the drop shadow, in px (0 = no shadow).
        var shadowMargin: Float = 0
        var clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        /// The source photo, drawn over everything but the brush at `uniforms.photo.x`.
        var photo: (any MTLTexture)? = nil
        /// A mosaic's painted bed (`TileScene.bed`), its ground under the bed finishes.
        var bed: (any MTLTexture)? = nil
        /// Tiles are being set: the lift pass draws them raised over their neighbours.
        var lift = false
    }

    /// Encodes one frame: outline coverage (RG16F, max blending), then a single multisampled
    /// pass with paper + shadow, all fills in one indexed draw, the outline composite, a mosaic's
    /// tiles still raised as they are set (their shadows, then the tiles), the numbers, the
    /// source photo while it shows and the brush.
    func encode(
        _ commands: any MTLCommandBuffer, scene: CanvasScene, states: any MTLBuffer,
        uniforms: CanvasUniforms, targets: Targets, content: Content
    ) {
        var u = uniforms
        let uniformSize = MemoryLayout<CanvasUniforms>.stride
        let drawOutlines = content.outlines && scene.segmentCount > 0

        if drawOutlines {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = targets.outlines
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            if let enc = commands.makeRenderCommandEncoder(descriptor: pass) {
                enc.label = "Outline coverage"
                enc.setRenderPipelineState(outlinePipeline)
                enc.setVertexBuffer(scene.points, offset: 0, index: 0)
                enc.setVertexBuffer(scene.segments, offset: 0, index: 1)
                enc.setVertexBuffer(scene.lineRegions, offset: 0, index: 2)
                enc.setVertexBuffer(states, offset: 0, index: 3)
                enc.setVertexBuffer(scene.regionColors, offset: 0, index: 4)
                enc.setVertexBytes(&u, length: uniformSize, index: 5)
                enc.setVertexBuffer(scene.lineLayers, offset: 0, index: 6)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.segmentCount)
                enc.endEncoding()
            }
        }

        let pass = MTLRenderPassDescriptor()
        let color = pass.colorAttachments[0]!
        if let msaa = targets.multisample {
            color.texture = msaa
            color.resolveTexture = targets.color
            color.storeAction = .multisampleResolve
        } else {
            color.texture = targets.color
            color.storeAction = .store
        }
        color.loadAction = .clear
        color.clearColor = content.clear
        guard let enc = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Canvas"

        var margin = content.shadowMargin
        enc.setRenderPipelineState(paperPipeline)
        enc.setVertexBytes(&u, length: uniformSize, index: 0)
        enc.setVertexBytes(&margin, length: MemoryLayout<Float>.size, index: 1)
        enc.setFragmentBytes(&u, length: uniformSize, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        let tiles = scene.tiles ?? noTiles
        let bodies = tiles.bodies(Self.finish(of: u))
        // Sampled only with `uniforms.tiles.z` set; something is bound either way.
        let bed = content.bed ?? atlasTexture
        if scene.indexCount > 0 {
            enc.setRenderPipelineState(fillPipeline)
            enc.setVertexBuffer(scene.positions, offset: 0, index: 0)
            enc.setVertexBuffer(scene.vertexRegions, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: uniformSize, index: 2)
            enc.setFragmentBuffer(scene.regionColors, offset: 0, index: 0)
            enc.setFragmentBuffer(states, offset: 0, index: 1)
            enc.setFragmentBytes(&u, length: uniformSize, index: 2)
            enc.setFragmentBuffer(tiles.shapes, offset: 0, index: 3)
            enc.setFragmentBuffer(tiles.corners, offset: 0, index: 4)
            enc.setFragmentBuffer(bodies, offset: 0, index: 5)
            enc.setFragmentTexture(bed, index: 0)
            enc.drawIndexedPrimitives(
                type: .triangle, indexCount: scene.indexCount, indexType: .uint32,
                indexBuffer: scene.indices, indexBufferOffset: 0)
        }

        if drawOutlines {
            // Outlines on the sheet's border reach past it.
            var outlineOverhang: Float = 2
            enc.setRenderPipelineState(compositePipeline)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setVertexBytes(&outlineOverhang, length: MemoryLayout<Float>.size, index: 1)
            enc.setFragmentTexture(targets.outlines, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if content.lift, scene.tiles != nil, scene.indexCount > 0 {
            enc.setRenderPipelineState(liftPipeline)
            enc.setVertexBuffer(scene.positions, offset: 0, index: 0)
            enc.setVertexBuffer(scene.vertexRegions, offset: 0, index: 1)
            enc.setVertexBytes(&u, length: uniformSize, index: 2)
            enc.setVertexBuffer(tiles.shapes, offset: 0, index: 3)
            enc.setVertexBuffer(states, offset: 0, index: 4)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.setFragmentBuffer(tiles.shapes, offset: 0, index: 1)
            enc.setFragmentBuffer(tiles.corners, offset: 0, index: 2)
            enc.setFragmentBuffer(bodies, offset: 0, index: 3)
            enc.setFragmentBuffer(states, offset: 0, index: 4)
            for shadow: UInt32 in [1, 0] {
                var pass = shadow
                enc.setVertexBytes(&pass, length: MemoryLayout<UInt32>.size, index: 5)
                enc.setFragmentBytes(&pass, length: MemoryLayout<UInt32>.size, index: 5)
                enc.drawIndexedPrimitives(
                    type: .triangle, indexCount: scene.indexCount, indexType: .uint32,
                    indexBuffer: scene.indices, indexBufferOffset: 0)
            }
        }

        if content.numbers && scene.glyphCount > 0 {
            enc.setRenderPipelineState(glyphPipeline)
            enc.setVertexBuffer(scene.glyphs, offset: 0, index: 0)
            enc.setVertexBuffer(scene.digitRects, offset: 0, index: 1)
            enc.setVertexBuffer(scene.digitUVs, offset: 0, index: 2)
            enc.setVertexBuffer(states, offset: 0, index: 3)
            enc.setVertexBuffer(scene.regionColors, offset: 0, index: 4)
            enc.setVertexBytes(&u, length: uniformSize, index: 5)
            enc.setFragmentTexture(atlasTexture, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: scene.glyphCount)
        }

        if let photo = content.photo, u.photo.x > 0 {
            var photoMargin: Float = 0
            enc.setRenderPipelineState(photoPipeline)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setVertexBytes(&photoMargin, length: MemoryLayout<Float>.size, index: 1)
            enc.setFragmentTexture(photo, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if content.brush {
            enc.setRenderPipelineState(brushPipeline)
            enc.setVertexBytes(&u, length: uniformSize, index: 0)
            enc.setFragmentBytes(&u, length: uniformSize, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
    }
}
