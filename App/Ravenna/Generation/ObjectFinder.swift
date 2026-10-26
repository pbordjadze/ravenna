import CoreGraphics
import CoreVideo
import Foundation
import os
import PaintCore

/// The main subjects of a photo, for a coloring book to close their silhouettes where the
/// detectors leave them open (`LineArtInput.objects`, `LineArtSettings.outlineObjects`): Vision's
/// foreground instance masks (the people, animals and objects a photo is of, from its
/// `SubjectVision` findings), every instance together, scaled to `maskLongSide`, cut at half,
/// traced by `MaskContours`.
///
/// The polygons are closed and normalized to the photo (0...1, origin top-left), largest
/// subject first, quantized by `MaskContours`, so small differences in Vision's output between
/// runs don't reorder or jitter them.
nonisolated enum ObjectFinder {
    /// The mask's long side: a silhouette traced at this size is smooth where the mask's
    /// edge is soft, and still within a few canvas pixels of the subject on a 1152-px canvas.
    static let maskLongSide = 384

    /// The subjects Vision finds in `image` (upright pixels), from its `SubjectVision` findings.
    /// Empty when there are none, or Vision can't run.
    static func objects(in image: CGImage) async -> [[SIMD2<Float>]] {
        guard let mask = await SubjectVision.findings(in: image).subjects else { return [] }
        return MaskContours.outlines(of: mask.inside, width: mask.width, height: mask.height)
    }

    /// The mask in `buffer` (one float or byte per pixel, 1 = subject) at `maskLongSide`: each
    /// output pixel inside when the mean of the pixels it covers is at least half.
    static func mask(from buffer: CVPixelBuffer) -> (inside: [Bool], width: Int, height: Int)? {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0 else { return nil }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let isFloat = format == kCVPixelFormatType_OneComponent32Float
        guard isFloat || format == kCVPixelFormatType_OneComponent8 else {
            Log.create.error("Subject mask in an unexpected pixel format \(format)")
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let scale = Double(maskLongSide) / Double(max(w, h))
        let ow = max(1, min(w, Int((Double(w) * scale).rounded()))), oh = max(1, min(h, Int((Double(h) * scale).rounded())))
        var sum = [Float](repeating: 0, count: ow * oh), count = [Int32](repeating: 0, count: ow * oh)
        for y in 0..<h {
            let row = base.advanced(by: y * stride)
            let oy = min(oh - 1, y * oh / h)
            for x in 0..<w {
                let value: Float = isFloat
                    ? row.load(fromByteOffset: x * 4, as: Float.self)
                    : Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255
                let o = oy * ow + min(ow - 1, x * ow / w)
                sum[o] += value
                count[o] += 1
            }
        }
        return (sum.indices.map { count[$0] > 0 && sum[$0] / Float(count[$0]) >= 0.5 }, ow, oh)
    }
}
