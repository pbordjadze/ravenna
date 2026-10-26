import CoreVideo
import Foundation
import Metal
import PaintCore

/// Replays a painting into video frames with the canvas shaders, for `TimelapseExporter`:
/// fills appear in the order they were painted, the one in progress spreads with the same
/// wet-paint animation as on the live canvas, and recent fills are still settling.
nonisolated final class TimelapseFrameRenderer {
    enum RenderError: Error { case unavailable, texture }

    private let context: RenderContext
    private let scene: CanvasScene
    private let order: [Int]
    private let origins: [SIMD2<Float>]
    private let radii: [Float]
    /// Region states per frame in flight (`TimelapseExporter.framesInFlight` slots).
    private let stateBuffers: [any MTLBuffer]
    private let options: CanvasSnapshot.Options
    private var cache: CVMetalTextureCache?
    private var targetSize = SIMD2<Int>(0, 0)
    private var multisample: (any MTLTexture)?
    private var outlines: (any MTLTexture)?

    init?(template: Template, progress: PaintProgress, options: CanvasSnapshot.Options = .thumbnail) {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        let origins = template.regions.indices.map { template.anchor(ofRegion: $0) }
        let radii = template.regions.indices.map { template.regions[$0].bounds.farthestCorner(from: origins[$0]) }
        let states = [RegionState](repeating: .settled(painted: false), count: template.regions.count)
        var stateBuffers: [any MTLBuffer] = []
        for _ in 0..<TimelapseExporter.framesInFlight {
            guard let buffer = CanvasScene.buffer(states, context.device) else { return nil }
            stateBuffers.append(buffer)
        }
        self.context = context
        self.scene = scene
        self.order = progress.log.map { Int($0.region) }
        self.origins = origins
        self.radii = radii
        self.stateBuffers = stateBuffers
        var options = options
        // Read once, not for every frame.
        if scene.isColoringBook && options.lineWeight == nil { options.lineWeight = .stored() }
        self.options = options
        CVMetalTextureCacheCreate(nil, nil, context.device, nil, &cache)
    }

    var strokeCount: Int { order.count }

    /// Starts drawing frame `frame`, the first `strokes` fills plus `fraction` of the next one,
    /// into a 32BGRA buffer, and returns the wait for its pixels. The frame's region states use
    /// slot `frame % framesInFlight`, which `TimelapseExporter` guarantees is free again (the
    /// intermediate targets are shared: Metal orders command buffers of one queue that use them).
    func render(frame: Int, strokes: Int, fraction: Float, into buffer: CVPixelBuffer) throws -> TimelapseExporter.FrameCompletion {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let stateBuffer = stateBuffers[frame % stateBuffers.count]
        let states = stateBuffer.contents().bindMemory(to: RegionState.self, capacity: max(1, scene.regionCount))
        // Time is measured in strokes: the renderer clock is 0, a fill started `age` strokes ago.
        for (k, r) in order.enumerated() {
            let age = Float(strokes - k) + fraction
            if k < strokes || (k == strokes && fraction > 0) {
                states[r] = RegionState(
                    origin: origins[r], start: -age, duration: 1, radius: radii[r], painted: 1,
                    seed: RegionState.frontSeed(forRegion: r))
            } else {
                states[r] = .settled(painted: false)
            }
        }

        var cvTexture: CVMetalTexture?
        guard let cache,
              CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, RenderContext.colorFormat, w, h, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture)
        else { throw RenderError.texture }
        let size = SIMD2(w, h)
        if size != targetSize || outlines == nil {
            multisample = context.makeMultisampleTarget(width: w, height: h)
            outlines = context.makeOutlineTarget(width: w, height: h)
            targetSize = size
        }
        guard let outlines, let commands = context.queue.makeCommandBuffer() else { throw RenderError.unavailable }
        let u = CanvasSnapshot.uniforms(scene: scene, width: w, height: h, options: options)
        let background = u.background
        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: u,
            targets: RenderContext.Targets(color: texture, multisample: multisample, outlines: outlines),
            content: RenderContext.Content(
                outlines: options.drawsLines(for: scene), numbers: options.numbers,
                clear: MTLClearColor(red: Double(background.x), green: Double(background.y), blue: Double(background.z), alpha: 1)))
        commands.commit()
        return {
            commands.waitUntilCompleted()
            // A texture from the cache must outlive the GPU's writes into its pixel buffer.
            withExtendedLifetime(cvTexture) {}
            // Metal refuses GPU work from a backgrounded app: fail rather than encode blank frames.
            guard commands.status == .completed else { throw RenderError.unavailable }
            // The pixels are Display P3; tag them so encoders and players keep the true paint colors.
            // The transfer stays BT.709 (Apple's example for Metal buffers): nothing documents that HEVC accepts sRGB beside P3.
            CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_P3_D65, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        }
    }

    /// Exports the replay of `progress` as a movie at `url`.
    @concurrent
    static func export(
        template: Template, progress: PaintProgress, to url: URL, longSide: Int = 1080,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        guard let renderer = TimelapseFrameRenderer(template: template, progress: progress) else { throw RenderError.unavailable }
        let size = CanvasSnapshot.fittedSize(for: template, longSide: longSide)
        try await TimelapseExporter.export(
            strokeCount: renderer.strokeCount, options: TimelapseExporter.Options(size: size), to: url, progress: onProgress
        ) { index, strokes, fraction, buffer in
            try renderer.render(frame: index, strokes: strokes, fraction: fraction, into: buffer)
        }
    }
}
