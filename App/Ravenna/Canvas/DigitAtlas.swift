import CoreGraphics
import CoreText
import Foundation
import PaintCore
import UIKit

/// Signed-distance-field atlas of the digits 0–9 in New York Bold (the system serif), generated
/// at runtime.
///
/// Each digit is rasterized supersampled, turned into a signed distance with an exact EDT
/// and box-filtered down, so numbers stay crisp from 6 pt to full screen with one texture.
nonisolated struct DigitAtlas: Sendable {
    let width: Int
    let height: Int
    /// R8: 0.5 on the glyph outline, > 0.5 inside.
    let pixels: [UInt8]
    /// Per digit: quad in em relative to the pen position (x) and the digits' vertical
    /// centre (y, down): minX, minY, maxX, maxY.
    let rects: [SIMD4<Float>]
    /// Per digit: texture coordinates u0, v0, u1, v1.
    let uvs: [SIMD4<Float>]
    /// Per digit advance in em: places the digits of a run. How big a run is drawn is
    /// `LabelSizing`'s decision, shared with every other renderer.
    let advances: [Float]

    static func make(fontSize: Int = 64, spread: Int = 8, supersample: Int = 3) -> DigitAtlas? {
        let ss = supersample
        let size = CGFloat(fontSize * ss)
        let font = numeralFont(size: size)
        var chars = Array("0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: 10)
        guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, 10) else { return nil }
        var boxes = [CGRect](repeating: .zero, count: 10)
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &boxes, 10)
        var advances = [CGSize](repeating: .zero, count: 10)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, 10)
        let cap = CTFontGetCapHeight(font)

        let pad = CGFloat(spread * ss)
        let yMin = floor(boxes.map(\.minY).min() ?? 0)
        let yMax = ceil(boxes.map(\.maxY).max() ?? size)
        let cellH = roundUp(Int(ceil(yMax - yMin + 2 * pad)), to: ss)

        var cells: [(width: Int, values: [UInt8])] = []
        var rects: [SIMD4<Float>] = []
        for d in 0..<10 {
            let box = boxes[d]
            let x0 = floor(box.minX)
            let cellW = roundUp(Int(ceil(box.maxX - x0 + 2 * pad)), to: ss)
            guard let coverage = rasterize(font: font, glyph: glyphs[d], width: cellW, height: cellH,
                                           origin: CGPoint(x: pad - x0, y: pad - yMin))
            else { return nil }
            cells.append((cellW / ss, distanceField(coverage, width: cellW, height: cellH, supersample: ss, spread: spread)))
            let minX = Float((x0 - pad) / size)
            let minY = -Float((CGFloat(cellH) - pad + yMin - cap / 2) / size)
            rects.append(SIMD4(minX, minY, minX + Float(CGFloat(cellW) / size), minY + Float(CGFloat(cellH) / size)))
        }

        // Pack side by side with a 2 px gutter.
        let gutter = 2
        let atlasW = cells.reduce(gutter) { $0 + $1.width + gutter }
        let cellHf = cellH / ss
        let atlasH = cellHf + 2 * gutter
        var pixels = [UInt8](repeating: 0, count: atlasW * atlasH)
        var uvs: [SIMD4<Float>] = []
        var x = gutter
        for cell in cells {
            for row in 0..<cellHf {
                for col in 0..<cell.width {
                    pixels[(row + gutter) * atlasW + x + col] = cell.values[row * cell.width + col]
                }
            }
            uvs.append(SIMD4(
                Float(x) / Float(atlasW), Float(gutter) / Float(atlasH),
                Float(x + cell.width) / Float(atlasW), Float(gutter + cellHf) / Float(atlasH)))
            x += cell.width + gutter
        }
        return DigitAtlas(
            width: atlasW, height: atlasH, pixels: pixels, rects: rects, uvs: uvs,
            advances: advances.map { Float($0.width / size) })
    }

    /// Width in em of the digit run for `number`.
    func runWidth(_ digits: [Int]) -> Float { digits.reduce(0) { $0 + advances[$1] } }

    private static func roundUp(_ v: Int, to m: Int) -> Int { (v + m - 1) / m * m }

    private static func numeralFont(size: CGFloat) -> CTFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size) as CTFont
    }

    /// Glyph coverage 0…1, row 0 at the top.
    private static func rasterize(font: CTFont, glyph: CGGlyph, width: Int, height: Int, origin: CGPoint) -> [Float]? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
            let data = ctx.data
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(gray: 1, alpha: 1)
        var g = glyph
        var p = origin
        CTFontDrawGlyphs(font, &g, &p, 1, ctx)
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let stride = ctx.bytesPerRow
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { out[y * width + x] = Float(bytes[y * stride + x]) / 255 }
        }
        return out
    }

    /// Signed distance (supersampled EDT, box-filtered down) encoded as 0.5 − d / (2·spread).
    private static func distanceField(_ coverage: [Float], width: Int, height: Int, supersample ss: Int, spread: Int) -> [UInt8] {
        let inside = coverage.map { $0 >= 0.5 }
        let toInside = DistanceTransform.squaredEDT(width: width, height: height) { inside[$0] }
        let toOutside = DistanceTransform.squaredEDT(width: width, height: height) { !inside[$0] }
        let w = width / ss, h = height / ss
        var out = [UInt8](repeating: 0, count: w * h)
        let norm = 1 / Float(ss * ss)
        for y in 0..<h {
            for x in 0..<w {
                var sum: Float = 0
                for sy in 0..<ss {
                    for sx in 0..<ss {
                        let i = (y * ss + sy) * width + x * ss + sx
                        // Pixel centres sit half a pixel from the true edge.
                        sum += inside[i] ? -(toOutside.storage[i].squareRoot() - 0.5) : toInside.storage[i].squareRoot() - 0.5
                    }
                }
                let d = sum * norm / Float(ss)   // final pixels, + outside
                let v = min(max(0.5 - d / Float(2 * spread), 0), 1)
                out[y * w + x] = UInt8((v * 255).rounded())
            }
        }
        return out
    }
}
