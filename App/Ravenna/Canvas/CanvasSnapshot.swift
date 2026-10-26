import CoreGraphics
import Foundation
import Metal
import PaintCore

/// Offscreen rendering with the canvas shaders: the finished painting's share picture
/// (`CompletionShare`), the time-lapse's frames (`TimelapseFrameRenderer` uses its uniforms)
/// and the render tests. Thumbnails, shared images, previews and PDFs are `TemplateRasterizer`'s.
/// Thread-safe; call it off the main actor.
nonisolated enum CanvasSnapshot {
    nonisolated struct Options: Sendable {
        var outlines: Bool
        var numbers: Bool
        /// Outline width in output pixels per canvas unit of scale (≥ 1 px is kept crisp).
        var outlineWidth: Float = 1.1
        /// Light paper unless a test asks for another palette; exports never do.
        var palette = CanvasPalette.light
        /// Palette index whose unpainted regions get the selection highlight.
        var highlight: Int?
        /// How heavy a coloring book's drawing is; nil = Settings › Line Weight.
        var lineWeight: LineWeight?

        /// The artwork as painted so far: unpainted regions stay paper, no line art (a coloring
        /// book keeps its drawing, `drawsLines(for:)`).
        static let painting = Options(outlines: false, numbers: false)
        /// Line art and numbers over the paint (render tests).
        static let preview = Options(outlines: true, numbers: true)
        /// The time-lapse's look: paint plus faint line art, no numbers.
        static let thumbnail = Options(outlines: true, numbers: false, outlineWidth: 0.8)

        /// Whether `scene`'s line art is drawn: with `outlines`, and always for a coloring book,
        /// whose drawing is part of the picture.
        func drawsLines(for scene: CanvasScene) -> Bool { outlines || scene.isColoringBook }
    }

    /// Renders `template` with `progress` (nil = nothing painted) into an image of `size`
    /// pixels; the canvas is fitted and centred, any letterbox is transparent.
    static func render(template: Template, progress: PaintProgress?, size: CGSize, options: Options = .painting) -> CGImage? {
        guard let context = RenderContext.shared, let scene = CanvasScene(template: template, context: context) else { return nil }
        let painted = (0..<template.regions.count).map { progress?.isPainted($0) ?? false }
        return render(scene: scene, painted: painted, size: size, options: options, context: context)
    }

    /// `scene` with the regions `painted` says (one flag per region), as `render(template:…)`;
    /// with a `rect`, only that part of the canvas, as `render(template:progress:rect:…)`.
    static func render(
        scene: CanvasScene, painted: [Bool], size: CGSize, options: Options, context: RenderContext, rect: CGRect? = nil
    ) -> CGImage? {
        let w = min(8192, max(1, Int(size.width.rounded()))), h = min(8192, max(1, Int(size.height.rounded())))
        return image(
            scene: scene, states: painted.map(RegionState.settled(painted:)),
            uniforms: uniforms(scene: scene, width: w, height: h, options: options, rect: rect),
            content: RenderContext.Content(outlines: options.drawsLines(for: scene), numbers: options.numbers),
            width: w, height: h, context: context)
    }

    /// A close-up: `rect` of the canvas (canvas units) scaled to fill `size` pixels, with
    /// `progress` (nil = nothing painted). Feedback renders what a mark covers and what was in
    /// view this way. Lines stay as fine as at `closeUpLineScale` pixels per unit and numbers
    /// as large as `closeUpMaxFontPixels`, as the zoomed canvas keeps them.
    static func render(template: Template, progress: PaintProgress?, rect: CGRect, size: CGSize, options: Options) -> CGImage? {
        guard rect.width > 0, rect.height > 0, let context = RenderContext.shared,
              let scene = CanvasScene(template: template, context: context)
        else { return nil }
        let painted = (0..<template.regions.count).map { progress?.isPainted($0) ?? false }
        return render(scene: scene, painted: painted, size: size, options: options, context: context, rect: rect)
    }

    static let closeUpLineScale: Float = 2
    static let closeUpMaxFontPixels: Float = 44

    /// One frame of `scene` with these region states, uniforms and passes, read back as a
    /// Display P3 image of `w`×`h` pixels.
    static func image(
        scene: CanvasScene, states: [RegionState], uniforms: CanvasUniforms, content: RenderContext.Content,
        width w: Int, height h: Int, context: RenderContext
    ) -> CGImage? {
        let device = context.device
        let rowBytes = (w * 4 + 255) / 256 * 256
        guard let stateBuffer = CanvasScene.buffer(states, device),
              let color = context.makeColorTarget(width: w, height: h),
              let outlines = context.makeOutlineTarget(width: w, height: h),
              let readback = device.makeBuffer(length: rowBytes * h, options: .storageModeShared),
              let commands = context.queue.makeCommandBuffer()
        else { return nil }
        context.encode(
            commands, scene: scene, states: stateBuffer, uniforms: uniforms,
            targets: RenderContext.Targets(
                color: color, multisample: context.makeMultisampleTarget(width: w, height: h), outlines: outlines),
            content: content)
        guard let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: w, height: h, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * h)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }

        let data = Data(bytes: readback.contents(), count: rowBytes * h)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3)
        else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Shader constants for an offscreen frame: canvas fitted and centred in `width`×`height`
    /// pixels, renderer clock at 0. With a `rect` (canvas units), that part of the canvas is
    /// fitted and centred instead, as a close-up (`render(template:progress:rect:…)`).
    static func uniforms(scene: CanvasScene, width w: Int, height h: Int, options: Options, rect: CGRect? = nil) -> CanvasUniforms {
        let canvasW = scene.canvasSize.x, canvasH = scene.canvasSize.y
        let shown = rect.map { (x: Float($0.minX), y: Float($0.minY), w: Float($0.width), h: Float($0.height)) }
            ?? (x: 0, y: 0, w: canvasW, h: canvasH)
        let scale = min(Float(w) / shown.w, Float(h) / shown.h)
        let highlight = options.highlight.flatMap { $0 >= 0 && $0 < scene.paletteLinear.count ? $0 : nil }
        let width = options.outlineWidth * (rect == nil ? max(scale, 0.25) : min(max(scale, 0.25), closeUpLineScale))
        let lines: CanvasFrame.Lines = scene.isColoringBook
            ? .coloringBook(width: width * ColoringBookLook.widthFactor * (options.lineWeight ?? .stored()).factor)
            : .classic
        return CanvasUniforms(CanvasFrame(
            origin: SIMD2((Float(w) - shown.w * scale) / 2 - shown.x * scale, (Float(h) - shown.h * scale) / 2 - shown.y * scale),
            scale: scale, pointScale: 1,
            targetSize: SIMD2(Float(w), Float(h)), canvasSize: SIMD2(canvasW, canvasH),
            palette: options.palette, shadowOpacity: 0, outlineOpacity: options.palette.outlineOpacity,
            outlineWidth: width, selectedOutlineWidth: width, hatch: highlight == nil ? 0 : 1,
            numbersShown: options.numbers ? 1 : 0, lines: lines,
            labels: SIMD4(5, 7, rect == nil ? .greatestFiniteMagnitude : closeUpMaxFontPixels, 0),
            numbers: SIMD4(0.8, 0.9, 0.04, 0),
            time: SIMD4(0, CanvasClock.never, CanvasClock.never, CanvasClock.never),
            selection: highlight.map { (color: $0, paint: scene.paletteLinear[$0]) },
            hovered: -1, pulsing: -1, bumped: -1, brush: nil, shine: (start: CanvasClock.never, color: -1),
            photoOpacity: 0))
    }

    /// Output size for a template fitted into `longSide` pixels.
    static func fittedSize(for template: Template, longSide: Int) -> CGSize {
        let s = Double(longSide) / Double(max(template.width, template.height))
        return CGSize(width: (Double(template.width) * s).rounded(), height: (Double(template.height) * s).rounded())
    }
}
