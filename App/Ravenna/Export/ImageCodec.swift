import CoreGraphics
import Foundation
import ImageIO
import PaintCore
import UniformTypeIdentifiers

/// PNG/JPEG encoding and size-limited decoding via ImageIO (thread-safe, keeps the
/// embedded color profile, so Display P3 survives).
nonisolated enum ImageCodec {
    static func pngData(_ image: CGImage) -> Data? {
        encode(image, type: .png, properties: [:])
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.9) -> Data? {
        encode(image, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    /// Decodes an image file, downscaled so its long side is at most `maxPixelSize`.
    static func image(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    /// Decodes image data (a photo someone sent), downscaled so its long side is at most `maxPixelSize`.
    static func image(data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return image(from: source, maxPixelSize: maxPixelSize)
    }

    /// Returns `image` scaled down (never up) to fit `maxPixelSize`.
    static func downscaled(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(long)
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// The image at index 0 of `source`, decoded through the thumbnail path when `maxPixelSize`
    /// bounds it (orientation applied).
    static func image(from source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        guard let maxPixelSize else {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

nonisolated extension RGBColorSpace {
    /// The CoreGraphics color space pixels in this space are drawn and tagged with.
    var cgColorSpace: CGColorSpace {
        CGColorSpace(name: self == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
    }
}
