#if canImport(MosaicKit)
import MosaicKit
#endif

nonisolated extension MosaicEngine {
    /// The painted bed under the tiles (finish B's grout layer, `sketchbook/render.py`'s `bed`): the
    /// tiles' colours blurred over half a pitch, darker and greyer, as the beds under Byzantine
    /// tesserae were painted. `width × height` pixels spanning the mosaic's canvas, row-major sRGB.
    ///
    /// The mosaic doesn't carry its pitch, so it's read from the tiles: a whole tile is about the
    /// 95th percentile of their sizes, a pitch that and a joint.
    public static func bed(of mosaic: Mosaic, width: Int, height: Int) -> [SIMD3<Float>] {
        guard width > 0, height > 0 else { return [] }
        let n = width * height
        guard mosaic.width > 0, mosaic.height > 0, !mosaic.tiles.isEmpty else {
            return [SIMD3<Float>](repeating: mosaic.grout, count: n)
        }
        let sx = Double(width) / Double(mosaic.width), sy = Double(height) / Double(mosaic.height)
        var r = [Float](repeating: 0, count: n), g = r, b = r, cover = r
        var sides: [Float] = []
        sides.reserveCapacity(mosaic.tiles.count)
        var m: [UInt8] = []
        for t in mosaic.tiles where t.corners.count >= 3 && mosaic.palette.indices.contains(t.paint) {
            let poly = t.corners.map { SIMD2(Double($0.x) * sx, Double($0.y) * sy) }
            sides.append(Float(Polygon.area(t.corners.map { SIMD2(Double($0.x), Double($0.y)) }).squareRoot()))
            var lo = poly[0], hi = poly[0]
            for p in poly { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) }
            let x0 = Swift.max(Int(lo.x.rounded(.down)) - 1, 0), y0 = Swift.max(Int(lo.y.rounded(.down)) - 1, 0)
            let x1 = Swift.min(Int(hi.x.rounded(.up)) + 2, width), y1 = Swift.min(Int(hi.y.rounded(.up)) + 2, height)
            guard x1 > x0, y1 > y0 else { continue }
            let bw = x1 - x0, bh = y1 - y0
            m = [UInt8](repeating: 0, count: bw * bh)
            Polygon.fill(poly, origin: SIMD2(Double(x0), Double(y0)), quarter: true, into: &m, width: bw, height: bh)
            let c = mosaic.palette[t.paint]
            for yy in 0..<bh {
                for xx in 0..<bw where m[yy * bw + xx] != 0 {
                    let i = (y0 + yy) * width + x0 + xx
                    r[i] = c.x; g[i] = c.y; b[i] = c.z; cover[i] = 1
                }
            }
        }
        var ranked = sides
        let side = Double(Stats.percentile(&ranked, 95))
        let sigma = 0.5 * (side + 1) * (sx + sy) / 2
        func blur(_ p: [Float]) -> [Float] {
            Blur.gaussian(Plane(width: width, height: height, pixels: p), sigma: sigma).pixels
        }
        let br = blur(r), bg = blur(g), bb = blur(b), bc = blur(cover)
        let ok = FastOKLab()
        let shade = SIMD3<Float>(0.8, 0.65, 0.65)
        var out = [SIMD3<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            let k = 1 / Swift.max(bc[i], 1e-3)
            out[i] = OKLab.toRGB(ok.lab(SIMD3(br[i], bg[i], bb[i]) * k) * shade)
        }
        return out
    }
}
