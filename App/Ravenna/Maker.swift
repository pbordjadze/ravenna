import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Makes a mosaic from a photo on the device: the photo at its working size, its contours (HED),
/// its faces (Vision), the tiles (`MosaicEngine`) and the painted bed under them. The photo never
/// leaves the device.
nonisolated enum Maker {
    struct Made: Sendable {
        var mosaic: Mosaic
        var photo: Data
        var bed: Data
    }

    enum Stage: String, Sendable {
        case reading = "Reading the photo"
        case contours = "Finding its outlines"
        case faces = "Finding faces"
        case tiles = "Laying the tiles"
        case bed = "Painting the bed"
    }

    enum MakerError: Error { case unreadable }

    /// The working long side for a position of the Pieces slider, 0...1: 724 px (about half the
    /// standard count) to 1448 px (about twice), as the bundled mosaics' details.
    static func longSide(pieces: Double) -> Int { Int((724 + 724 * min(max(pieces, 0), 1)).rounded()) }

    /// `eyes`: how irises are coloured (issue #9's option).
    static func make(from data: Data, pieces: Double, eyes: MosaicEngine.Eyes = .asTheyLook,
                     stage: @Sendable (Stage) -> Void) throws -> Made {
        stage(.reading)
        let side = longSide(pieces: pieces)
        guard let image = oriented(data, longSide: side), case let (rgba, w, h)? = pixels(image) else { throw MakerError.unreadable }
        try Task.checkCancellation()

        stage(.contours)
        let hedSide = min(max(w, h), Contours.maximumLongSide)
        let contours: [Float]
        if hedSide == max(w, h) {
            contours = try Contours.map(rgba: rgba, width: w, height: h)
        } else {
            let k = Double(hedSide) / Double(max(w, h))
            let sw = max(1, Int((Double(w) * k).rounded())), sh = max(1, Int((Double(h) * k).rounded()))
            guard let small = scaled(image, width: sw, height: sh), case let (srgba, _, _)? = pixels(small) else { throw MakerError.unreadable }
            contours = bilinear(try Contours.map(rgba: srgba, width: sw, height: sh), sw, sh, to: w, h)
        }
        try Task.checkCancellation()

        stage(.faces)
        let faces = (try? Faces.find(in: image, rgba: rgba)) ?? []
        try Task.checkCancellation()

        stage(.tiles)
        var rgb = [SIMD3<Float>](repeating: .zero, count: w * h)
        for i in 0..<(w * h) { rgb[i] = SIMD3(Float(rgba[i * 4]), Float(rgba[i * 4 + 1]), Float(rgba[i * 4 + 2])) / 255 }
        var settings = MosaicEngine.Settings()
        settings.eyes = eyes
        let mosaic = try MosaicEngine.make(photo: .init(width: w, height: h, rgb: rgb), contours: contours, faces: faces,
                                           settings: settings, cancel: { Task.isCancelled })

        stage(.bed)
        let bed = MosaicEngine.bed(of: mosaic, width: w, height: h)
        guard let photo = jpeg(image), let bedImage = cgImage(bed, w, h), let bedData = jpeg(bedImage) else { throw MakerError.unreadable }
        return Made(mosaic: mosaic, photo: photo, bed: bedData)
    }

    /// The photo upright, scaled down to `longSide` (never up).
    static func oriented(_ data: Data, longSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image in sRGB, 4 bytes a pixel, on black (photos are opaque).
    static func pixels(_ image: CGImage) -> ([UInt8], Int, Int)? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (bytes, w, h) : nil
    }

    static func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// A map resampled bilinearly (pixel centres aligned, as cv2's INTER_LINEAR).
    static func bilinear(_ m: [Float], _ w: Int, _ h: Int, to W: Int, _ H: Int) -> [Float] {
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

    static func cgImage(_ rgb: [SIMD3<Float>], _ w: Int, _ h: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<min(rgb.count, w * h) {
            let c = rgb[i]
            bytes[i * 4] = UInt8(min(max(c.x, 0), 1) * 255)
            bytes[i * 4 + 1] = UInt8(min(max(c.y, 0), 1) * 255)
            bytes[i * 4 + 2] = UInt8(min(max(c.z, 0), 1) * 255)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }
}
