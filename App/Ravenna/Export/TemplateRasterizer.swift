import CoreGraphics
import CoreText
import Foundation
import PaintCore
import simd

/// CoreGraphics rendering of a template and its progress: gallery thumbnails, share
/// images, create-flow previews and PDF pages. No Metal, safe off the main actor.
///
/// Uses the template's vector geometry when present (crisp at any size, vector in PDFs)
/// and otherwise samples the raster region map. Line art draws as a coloring book: the drawing
/// in full ink over everything (`ColoringBookLook`), in every style, with dotted guides along
/// its color edges on paper.
nonisolated enum TemplateRasterizer {
    struct Style: Sendable {
        enum Unpainted: Sendable, Equatable {
            /// Plain paper.
            case paper
            /// A pale grey at the region's final lightness, like a pencil study of the
            /// picture, so partly painted thumbnails stay recognizable.
            case sketch
        }

        /// Where a coloring book's drawing goes (classic templates draw every line alike).
        enum Lines: Sendable, Equatable {
            /// As the canvas shows it.
            case screen
            /// On paper, where no highlight shows a color's cells: the color edges as dotted guides.
            case print
        }

        var unpainted: Unpainted = .paper
        /// Render every region painted (the finished picture).
        var paintAll = false
        /// Outline width in output pixels (points for PDF); 0 disables outlines.
        var outlineWidth: CGFloat = 1
        /// Encoded RGBA in the template's color space.
        var outlineColor = SIMD4<Float>(0.52, 0.54, 0.57, 1)
        /// Omit outlines between two painted regions so finished areas read as paint.
        var hidesOutlinesBetweenPainted = true
        var numbers = false
        var numberColor = SIMD4<Float>(0.38, 0.40, 0.43, 1)
        /// Largest number as a fraction of the canvas' long side (`LabelSizing`'s for sheets);
        /// big regions carry several labels of this size rather than one huge number.
        var maximumNumberFraction = CGFloat(LabelSizing.sheetMaximumFraction)
        var paper = SIMD3<Float>(1, 1, 1)
        var lines = Lines.screen
        /// Draw a coloring book's drawing (off: the paint alone, for a drawing laid over it).
        var drawsDrawing = true
        /// How heavy a coloring book's drawing is; nil = Settings › Line Weight.
        var lineWeight: LineWeight?

        /// Gallery thumbnails: painted regions in color, the rest a faint sketch.
        static let thumbnail = Style(
            unpainted: .sketch, outlineWidth: 0.9, outlineColor: SIMD4(0.45, 0.46, 0.49, 0.28))
        /// The finished painting, with a whisper of the lines it was painted in.
        static let finished = Style(
            paintAll: true, outlineWidth: 0.8, outlineColor: SIMD4(0.2, 0.2, 0.22, 0.10),
            hidesOutlinesBetweenPainted: false)
        /// Painted preview (create flow): no outlines, only a coloring book's drawing.
        static let painting = Style(paintAll: true, outlineWidth: 0)
        /// Every area in its paint and nothing else: Refine's painting, under its own drawing.
        static let paintedAreas = Style(paintAll: true, outlineWidth: 0, drawsDrawing: false)
        /// Printable template (PDF): hairlines and small numbers. `PDFExporter` picks a scale
        /// at which the smallest number is still legible on paper.
        static let printable = Style(
            outlineWidth: 0.4, outlineColor: SIMD4(0.45, 0.47, 0.5, 1), numbers: true,
            numberColor: SIMD4(0.35, 0.37, 0.4, 1), lines: .print)
    }

    // MARK: Entry points

    /// Pixel size of a render whose long side is `maxPixelSize`, keeping the template's aspect.
    static func pixelSize(of t: Template, maxPixelSize: Int) -> (width: Int, height: Int) {
        let long = max(t.width, t.height)
        let scale = Double(maxPixelSize) / Double(max(1, long))
        return (max(1, Int((Double(t.width) * scale).rounded())), max(1, Int((Double(t.height) * scale).rounded())))
    }

    /// Renders to an image whose long side is `maxPixelSize` pixels.
    /// - Parameter painted: Painted flag per region (`PaintProgress.painted`); nil = none.
    static func image(_ t: Template, painted: [Bool]? = nil, style: Style, maxPixelSize: Int) -> CGImage? {
        let size = pixelSize(of: t, maxPixelSize: maxPixelSize)
        guard let ctx = makeContext(width: size.width, height: size.height, colorSpace: t.colorSpace) else { return nil }
        draw(t, painted: painted, style: style, in: ctx, rect: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return ctx.makeImage()
    }

    static func pngData(_ t: Template, painted: [Bool]? = nil, style: Style, maxPixelSize: Int) -> Data? {
        image(t, painted: painted, style: style, maxPixelSize: maxPixelSize).flatMap(ImageCodec.pngData)
    }

    /// A bitmap context whose user space is y-down (origin top-left), like canvas units.
    static func makeContext(width: Int, height: Int, colorSpace: RGBColorSpace) -> CGContext? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace.cgColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    /// Draws the template into `rect` of a y-down context (bitmap or PDF page).
    /// - Parameter rasterResolution: Pixel size used for the region-map fallback; defaults
    ///   to the device size of `rect`.
    static func draw(
        _ t: Template, painted: [Bool]?, style: Style, in ctx: CGContext, rect: CGRect,
        rasterResolution: CGSize? = nil
    ) {
        guard t.width > 0, t.height > 0, rect.width > 0, rect.height > 0 else { return }
        let flags = resolvedPainted(t, painted: painted, style: style)
        let scale = min(rect.width / CGFloat(t.width), rect.height / CGFloat(t.height))
        let deviceSize = rasterResolution ?? ctx.convertToDeviceSpace(rect).standardized.size

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(cgColor(SIMD4(style.paper, 1), space: t.colorSpace))
        ctx.fill(rect)
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: rect.width / CGFloat(t.width), y: rect.height / CGFloat(t.height))

        if t.rings.isEmpty {
            drawRegionMap(t, painted: flags, style: style, in: ctx, resolution: deviceSize)
        } else {
            drawVectorFills(t, painted: flags, style: style, in: ctx, scale: scale)
            if let lines = DrawableLineArt(t) {
                if style.drawsDrawing { drawBookOutlines(t, lines: lines, painted: flags, style: style, in: ctx, scale: scale) }
            } else if style.outlineWidth > 0 {
                drawVectorOutlines(t, painted: flags, style: style, in: ctx, scale: scale)
            }
        }
        if style.numbers { drawNumbers(t, painted: flags, style: style, in: ctx) }
        ctx.restoreGState()
    }

    // MARK: Colors

    static func cgColor(_ rgba: SIMD4<Float>, space: RGBColorSpace) -> CGColor {
        let components = [CGFloat(rgba.x), CGFloat(rgba.y), CGFloat(rgba.z), CGFloat(rgba.w)]
        return CGColor(colorSpace: space.cgColorSpace, components: components)
            ?? CGColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    /// The pale grey standing in for an unpainted region in `.sketch` mode.
    static func sketchColor(_ color: PaletteColor) -> SIMD3<Float> {
        let lightness = min(max(color.oklab.x, 0), 1)
        return SIMD3(repeating: 0.76 + 0.22 * lightness)
    }

    private static func resolvedPainted(_ t: Template, painted: [Bool]?, style: Style) -> [Bool] {
        if style.paintAll { return [Bool](repeating: true, count: t.regions.count) }
        guard let painted, painted.count == t.regions.count else { return [Bool](repeating: false, count: t.regions.count) }
        return painted
    }

    /// Fill of a region, or nil when it shows the paper.
    private static func fill(of region: Int, _ t: Template, painted: [Bool], style: Style) -> SIMD3<Float>? {
        let color = t.palette[Int(t.regions[region].colorIndex)]
        if painted[region] { return color.rgb }
        return style.unpainted == .sketch ? sketchColor(color) : nil
    }

    // MARK: Vector path

    private static func drawVectorFills(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat) {
        // One even-odd path per distinct fill. Regions never overlap, so even-odd over a
        // union of regions (outer rings + holes) fills exactly those regions.
        let paletteCount = t.palette.count
        var paths = [CGMutablePath?](repeating: nil, count: paletteCount * 2)
        for index in t.regions.indices {
            let color = Int(t.regions[index].colorIndex)
            let key: Int
            if painted[index] {
                key = color
            } else if style.unpainted == .sketch {
                key = paletteCount + color
            } else {
                continue
            }
            let path = paths[key] ?? CGMutablePath()
            for polygon in t.polygons(ofRegion: index) where polygon.count >= 3 {
                path.move(to: CGPoint(polygon[0]))
                for p in polygon.dropFirst() { path.addLine(to: CGPoint(p)) }
                path.closeSubpath()
            }
            paths[key] = path
        }
        // A hairline in the fill color closes anti-aliasing seams between neighbours.
        let seam = 0.7 / max(scale, 0.0001)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(seam)
        for (key, path) in paths.enumerated() {
            guard let path else { continue }
            let rgb = key < paletteCount ? t.palette[key].rgb : sketchColor(t.palette[key - paletteCount])
            let color = cgColor(SIMD4(rgb, 1), space: t.colorSpace)
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            ctx.addPath(path)
            ctx.drawPath(using: .eoFillStroke)
        }
    }

    private static func drawVectorOutlines(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat) {
        // A PDF sheet shows part of a large template: edges outside it would still bloat the file.
        let visible = ctx.boundingBoxOfClipPath
        let path = CGMutablePath()
        for edge in t.edges where edge.right != BoundaryEdge.outside {
            if style.hidesOutlinesBetweenPainted && painted[Int(edge.left)] && painted[Int(edge.right)] { continue }
            addPolyline(t.points(of: edge), to: path, within: visible)
        }
        ctx.setStrokeColor(cgColor(style.outlineColor, space: t.colorSpace))
        ctx.setLineWidth(style.outlineWidth / max(scale, 0.0001))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// A coloring book's lines (`ColoringBookLook`): the drawing (every drawn layer, edges and
    /// strokes alike) in full ink, `widthFactor` times the style's line (a style without lines
    /// still gets it at the finished picture's width: the drawing is part of the picture), never
    /// hidden by paint, except writing over a painted paint too dark for the ink
    /// (`DrawableLineArt.lightWriting`), which is in the style's paper tone, as on the canvas. On
    /// paper (`.print`), where no highlight shows a color's cells and nothing is painted, the
    /// color edges go underneath first, as dotted guides.
    private static func drawBookOutlines(
        _ t: Template, lines: DrawableLineArt, painted: [Bool], style: Style, in ctx: CGContext, scale: CGFloat
    ) {
        let visible = ctx.boundingBoxOfClipPath
        let units = 1 / max(scale, 0.0001)
        let weight = (style.lineWeight ?? .stored()).factor
        let base = style.outlineWidth > 0 ? style.outlineWidth : Style.finished.outlineWidth
        ctx.saveGState()
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        if style.lines == .print {
            let guides = CGMutablePath()
            for (e, edge) in t.edges.enumerated()
            where edge.right != BoundaryEdge.outside && !DrawableLineArt.isDrawn(lines.edgeLayers[e]) {
                addPolyline(t.points(of: edge), to: guides, within: visible)
            }
            if !guides.isEmpty {
                let c = style.outlineColor
                ctx.setStrokeColor(cgColor(SIMD4(c.x, c.y, c.z, c.w * ColoringBookLook.printedGuideOpacity), space: t.colorSpace))
                let width = style.outlineWidth * units
                ctx.setLineWidth(width)
                // Round caps on zero-length dashes: dots.
                ctx.setLineDash(phase: 0, lengths: [0, width * ColoringBookLook.printedGuideSpacing])
                ctx.addPath(guides)
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        let drawing = CGMutablePath(), light = CGMutablePath()
        for (e, edge) in t.edges.enumerated() where edge.right != BoundaryEdge.outside && DrawableLineArt.isDrawn(lines.edgeLayers[e]) {
            addPolyline(t.points(of: edge), to: drawing, within: visible)
        }
        for (k, stroke) in lines.strokes.enumerated() where DrawableLineArt.isDrawn(stroke.layer) {
            let onPaint = style.lines == .screen && lines.lightWriting[k] && painted[Int(stroke.region)]
            addPolyline(lines.points(of: stroke), to: onPaint ? light : drawing, within: visible)
        }
        ctx.setStrokeColor(cgColor(ColoringBookLook.ink, space: t.colorSpace))
        ctx.setLineWidth(base * CGFloat(ColoringBookLook.widthFactor * weight) * units)
        ctx.addPath(drawing)
        ctx.strokePath()
        if !light.isEmpty {
            ctx.setStrokeColor(cgColor(SIMD4(style.paper, 1), space: t.colorSpace))
            ctx.addPath(light)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Appends an open polyline to `path` unless it lies outside `visible`.
    private static func addPolyline(_ points: ArraySlice<SIMD2<Float>>, to path: CGMutablePath, within visible: CGRect) {
        guard let first = points.first else { return }
        var low = first, high = first
        for p in points {
            low = pointwiseMin(low, p)
            high = pointwiseMax(high, p)
        }
        // Padded by a unit so straight edges get a box with area.
        let box = CGRect(x: CGFloat(low.x) - 1, y: CGFloat(low.y) - 1, width: CGFloat(high.x - low.x) + 2, height: CGFloat(high.y - low.y) + 2)
        guard visible.intersects(box) else { return }
        path.move(to: CGPoint(first))
        for p in points.dropFirst() { path.addLine(to: CGPoint(p)) }
    }

    // MARK: Region-map fallback

    /// Rasterizes the region map (used while a template has no vector geometry). Renders
    /// at the larger of the template and output resolution, so downscaled thumbnails get
    /// filtered and enlarged exports keep 1-pixel outlines.
    private static func drawRegionMap(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext, resolution: CGSize) {
        let outW = Int(resolution.width.rounded()), outH = Int(resolution.height.rounded())
        let w = min(max(t.width, outW), 8192), h = min(max(t.height, outH), 8192)
        guard let image = regionMapImage(t, painted: painted, style: style, width: w, height: h) else { return }
        ctx.saveGState()
        // Images draw y-up; undo the y-down flip locally.
        ctx.translateBy(x: 0, y: CGFloat(t.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: t.width, height: t.height))
        ctx.restoreGState()
    }

    static func regionMapImage(_ t: Template, painted: [Bool], style: Style, width w: Int, height h: Int) -> CGImage? {
        func pack(_ rgb: SIMD3<Float>) -> UInt32 {
            let c = (rgb.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1)) * 255).rounded(.toNearestOrAwayFromZero)
            return UInt32(c.x) | UInt32(c.y) << 8 | UInt32(c.z) << 16 | 0xFF00_0000
        }
        let fills = t.regions.indices.map { fill(of: $0, t, painted: painted, style: style) ?? style.paper }
        let outline = style.outlineColor
        let alpha = style.outlineWidth > 0 ? outline.w * Float(min(style.outlineWidth, 1)) : 0
        let colors = fills.map(pack)
        let outlined = fills.map { pack($0 * (1 - alpha) + SIMD3(outline.x, outline.y, outline.z) * alpha) }
        let hides = style.hidesOutlinesBetweenPainted
        let xs = (0..<w).map { min(t.width - 1, Int((Double($0) + 0.5) * Double(t.width) / Double(w))) }
        let ys = (0..<h).map { min(t.height - 1, Int((Double($0) + 0.5) * Double(t.height) / Double(h))) }

        var pixels = [UInt32](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBufferPointer { out in
            t.regionMap.storage.withUnsafeBufferPointer { map in
                for y in 0..<h {
                    let row = ys[y] * t.width
                    let below = (y + 1 < h ? ys[y + 1] : ys[y]) * t.width
                    for x in 0..<w {
                        let r = Int(map[row + xs[x]])
                        var boundary = false
                        if alpha > 0 {
                            let right = x + 1 < w ? Int(map[row + xs[x + 1]]) : r
                            let down = Int(map[below + xs[x]])
                            boundary = (right != r && !(hides && painted[r] && painted[right]))
                                || (down != r && !(hides && painted[r] && painted[down]))
                        }
                        out[y * w + x] = boundary ? outlined[r] : colors[r]
                    }
                }
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: t.colorSpace.cgColorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Numbers

    /// Reference size the number glyph runs are laid out at, then scaled per label.
    private static let referenceFontSize: CGFloat = 100

    private static func drawNumbers(_ t: Template, painted: [Bool], style: Style, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(.system, referenceFontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, referenceFontSize, nil)
        let capHeight = CTFontGetCapHeight(font)
        var lines: [Int: (line: CTLine, width: CGFloat)] = [:]
        func line(for number: Int) -> (line: CTLine, width: CGFloat) {
            if let cached = lines[number] { return cached }
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: attributes))
            let entry = (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            lines[number] = entry
            return entry
        }

        ctx.saveGState()
        ctx.setFillColor(cgColor(style.numberColor, space: t.colorSpace))
        // y-down user space: flip glyphs upright.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let maximumSize = style.maximumNumberFraction * CGFloat(max(t.width, t.height))
        let visible = ctx.boundingBoxOfClipPath
        for label in t.labels {
            let region = Int(label.region)
            guard region < painted.count, !painted[region] else { continue }
            let number = Int(t.regions[region].colorIndex) + 1
            let digits = LabelSizing.digitCount(of: number)
            // The shared rule at any output scale: a number keeps to its region's room, a detail
            // area's down to its own floor. Output media make sure that is legible
            // (`PDFExporter` prints large templates on sheets).
            let size = CGFloat(LabelSizing.fontSize(
                radius: label.radius, digits: digits, maximum: Float(maximumSize), detail: t.isDetailRegion(region)))
            let reach = size * CGFloat(digits)
            guard visible.insetBy(dx: -reach, dy: -reach).contains(CGPoint(label.position)) else { continue }
            let run = line(for: number)
            let s = size / referenceFontSize
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(label.position.x), y: CGFloat(label.position.y))
            ctx.scaleBy(x: s, y: s)
            ctx.textPosition = CGPoint(x: -run.width / 2, y: capHeight / 2)
            CTLineDraw(run.line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

nonisolated extension CGPoint {
    init(_ p: SIMD2<Float>) { self.init(x: CGFloat(p.x), y: CGFloat(p.y)) }
}
