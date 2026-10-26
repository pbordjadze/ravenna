import CoreGraphics
import Foundation
import ImageIO
import PaintCore

/// Decodes photos into the pipeline's `RGBAImage` format.
///
/// Uses ImageIO's thumbnail path so a 48 MP HEIC is decoded straight to the size we need
/// (orientation applied, no full-resolution bitmap), and renders into Display P3 so the
/// wide-gamut colors of iPhone photos survive into the palette.
nonisolated enum PhotoLoader {
    enum LoadError: Error { case undecodable, contextFailed }

    static func load(data: Data, maxPixelSize: Int) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw LoadError.undecodable }
        return try load(source: source, maxPixelSize: maxPixelSize)
    }

    static func load(url: URL, maxPixelSize: Int) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw LoadError.undecodable }
        return try load(source: source, maxPixelSize: maxPixelSize)
    }

    private static func load(source: CGImageSource, maxPixelSize: Int) throws -> RGBAImage {
        guard let image = ImageCodec.image(from: source, maxPixelSize: maxPixelSize) else { throw LoadError.undecodable }
        return try rgbaImage(from: image)
    }

    /// Renders any CGImage into an 8-bit RGBA buffer (unpremultiplied), in Display P3 unless
    /// asked for sRGB (the edge detector's training space).
    static func rgbaImage(from image: CGImage, colorSpace: RGBColorSpace = .displayP3) throws -> RGBAImage {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = colorSpace.cgColorSpace
        let ok = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw LoadError.contextFailed }
        // Unpremultiply the (rare) translucent pixels.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = pixels[i + 3]
            if a != 255 && a != 0 {
                let s = 255 / Float(a)
                pixels[i] = UInt8(min(255, Float(pixels[i]) * s + 0.5))
                pixels[i + 1] = UInt8(min(255, Float(pixels[i + 1]) * s + 0.5))
                pixels[i + 2] = UInt8(min(255, Float(pixels[i + 2]) * s + 0.5))
            }
        }
        return RGBAImage(width: w, height: h, pixels: pixels, colorSpace: colorSpace)
    }

    /// Wraps an `RGBAImage` as a CGImage (for previews and export).
    static func cgImage(from image: RGBAImage) -> CGImage? {
        let space = image.colorSpace.cgColorSpace
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData) else { return nil }
        return CGImage(
            width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
