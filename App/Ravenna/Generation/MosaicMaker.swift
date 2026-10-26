import CoreGraphics
import Foundation
import MosaicCore
import MosaicEngine
import MosaicKit
import PaintCore

/// Ravenna's engine in the app, where Paint by Moonlight's `TemplateGenerator` was: a photo, cut to
/// its panel, made into a `Mosaic` (`MosaicEngine`) and that into the painting's template
/// (`MosaicCore.template(of:)`: region i is tile i, the last region the grout). Its contours come
/// from the HED model (`EdgeDetector`), its faces from Vision's landmarks (`SubjectVision`,
/// `MosaicFaces`), both found once a photo and panel (`analyze`) and laid at any size (`make`).
/// A library picture whose recipe a bundled mosaic stands for is laid from it (`bundled`). The
/// photo never leaves the device.
nonisolated enum MosaicMaker {
    enum MakerError: Error { case unreadable }

    /// What every mosaic of one framed photo is made from: its HED contour map and its faces'
    /// features, in the pixels of the map (the photo at `EdgeDetector.maximumLongSide` or less).
    struct Analysis: Sendable {
        let contours: EdgeMap
        let faces: [MosaicEngine.Face]
    }

    /// A mosaic and its template.
    struct Made: Sendable {
        var mosaic: Mosaic
        var template: Template
    }

    /// The long side drafts are made at while a slider moves: the recipe's tiles, smaller and
    /// finer (`Recipe.settings(side:)`), in about a third of the time.
    static let draftLongSide = 600

    /// `photo` cut to the recipe's panel (the whole of it for `.whole`).
    static func framed(_ photo: CGImage, panel: MosaicEngine.Panel, centre: SIMD2<Double>) -> CGImage {
        guard panel != .whole else { return photo }
        let w = Double(photo.width), h = Double(photo.height)
        let unit = panel.rect(width: w, height: h, centre: centre)
        let r = CGRect(x: unit.x * w, y: unit.y * h, width: unit.width * w, height: unit.height * h).integral
        return photo.cropping(to: r) ?? photo
    }

    /// The contours and faces of `framed`. Seconds of CPU (a VGG-16 pass and Vision's).
    @concurrent
    static func analyze(_ framed: CGImage) async throws -> Analysis {
        let size = EdgeDetector.mapSize(width: framed.width, height: framed.height, maxLongSide: EdgeDetector.maximumLongSide)
        let small = try pixels(of: framed, width: size.width, height: size.height)
        try Task.checkCancellation()
        let contours = try EdgeDetector.edgeMap(for: small, maxLongSide: EdgeDetector.maximumLongSide, cancel: .task)
        try Task.checkCancellation()
        let faces: [MosaicEngine.Face]
        if let image = PhotoLoader.cgImage(from: small) {
            let findings = await SubjectVision.findings(in: image)
            faces = MosaicFaces.features(findings, width: small.width, height: small.height, rgba: small.pixels)
        } else {
            faces = []
        }
        try Task.checkCancellation()
        return Analysis(contours: contours, faces: faces)
    }

    /// The bundled mosaic of library picture `sample` that `recipe` is (`Recipe.bundledDetail`),
    /// with the recipe's ground laid on; nil when there is none.
    static func bundled(_ sample: String?, recipe: MosaicEngine.Recipe) -> Mosaic? {
        guard let sample, let detail = recipe.bundledDetail,
              let url = Bundle.main.url(forResource: "\(sample)-\(detail.rawValue)", withExtension: "json"),
              let data = try? Data(contentsOf: url), let mosaic = try? JSONDecoder().decode(Mosaic.self, from: data)
        else { return nil }
        return recipe.laid(mosaic)
    }

    /// The mosaic of `framed` (whose `analysis` it is) as `recipe` lays it, at `side` px on its
    /// long side (the recipe's own, or a draft's), up or down from the photo's size, before its
    /// ground is laid on (`Recipe.laid`). Polls task
    /// cancellation; `progress` hears 0...1 from the engine's threads.
    static func make(
        _ framed: CGImage, analysis: Analysis, recipe: MosaicEngine.Recipe, side: Int,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> Mosaic {
        let long = max(framed.width, framed.height)
        guard long > 0 else { throw MakerError.unreadable }
        let k = Double(side) / Double(long)
        let w = max(Int((Double(framed.width) * k).rounded()), 16), h = max(Int((Double(framed.height) * k).rounded()), 16)
        let rgba = try pixels(of: framed, width: w, height: h)
        try Task.checkCancellation()
        var rgb = [SIMD3<Float>](repeating: .zero, count: w * h)
        rgba.pixels.withUnsafeBufferPointer { p in
            for i in 0..<(w * h) { rgb[i] = SIMD3(Float(p[i * 4]), Float(p[i * 4 + 1]), Float(p[i * 4 + 2])) / 255 }
        }
        let map = analysis.contours
        let contours = bilinear(map.values.map { Float($0) / 255 }, map.width, map.height, to: w, h)
        let scale = Float(w) / Float(max(map.width, 1))
        let faces = analysis.faces.map { $0.scaled(by: scale) }
        return try MosaicEngine.make(
            photo: .init(width: w, height: h, rgb: rgb), contours: contours, faces: faces,
            settings: recipe.settings(side: side), cancel: { Task.isCancelled }, progress: progress)
    }

    /// The painting's template of `mosaic`, which `Template.validate` passes.
    static func template(of mosaic: Mosaic) throws -> Template {
        try MosaicCore.template(of: mosaic)
    }

    /// `image` drawn at `width` × `height` (up or down) in sRGB, the engine's and HED's space.
    static func pixels(of image: CGImage, width: Int, height: Int) throws -> RGBAImage {
        if image.width == width, image.height == height { return try PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw MakerError.unreadable }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = ctx.makeImage() else { throw MakerError.unreadable }
        return try PhotoLoader.rgbaImage(from: scaled, colorSpace: .sRGB)
    }

    /// A map resampled bilinearly (pixel centres aligned, as cv2's INTER_LINEAR, which the
    /// sketchbook's maps were scaled with).
    static func bilinear(_ m: [Float], _ w: Int, _ h: Int, to W: Int, _ H: Int) -> [Float] {
        if w == W && h == H { return m }
        var out = [Float](repeating: 0, count: W * H)
        let sx = Float(w) / Float(W), sy = Float(h) / Float(H)
        for y in 0..<H {
            let fy = min(max((Float(y) + 0.5) * sy - 0.5, 0), Float(h - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, h - 1), ty = fy - Float(y0)
            for x in 0..<W {
                let fx = min(max((Float(x) + 0.5) * sx - 0.5, 0), Float(w - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, w - 1), tx = fx - Float(x0)
                let a = m[y0 * w + x0] * (1 - tx) + m[y0 * w + x1] * tx
                let b = m[y1 * w + x0] * (1 - tx) + m[y1 * w + x1] * tx
                out[y * W + x] = a * (1 - ty) + b * ty
            }
        }
        return out
    }
}
