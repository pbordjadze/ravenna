import Foundation
import Testing
@testable import MosaicEngine

/// The plain-Swift stand-ins for the OpenCV, SciPy and scikit-image calls the prototype makes.
@Suite("MosaicEngine primitives")
struct PrimitiveTests {
    typealias E = MosaicEngine

    static func random(_ w: Int, _ h: Int, density: Double, seed: UInt64) -> [UInt8] {
        var rng = E.SplitMix64(seed: seed)
        return (0..<(w * h)).map { _ in rng.unit() < density ? 1 : 0 }
    }

    @Test func distanceTransformIsExact() {
        let w = 23, h = 17
        let seed = Self.random(w, h, density: 0.05, seed: 7)
        let d = E.Distance.edt(seed: seed, width: w, height: h)
        let seeds = seed.indices.filter { seed[$0] != 0 }
        #expect(!seeds.isEmpty)
        for y in 0..<h {
            for x in 0..<w {
                var best = Float.infinity
                for s in seeds {
                    let dx = Float(s % w - x), dy = Float(s / w - y)
                    best = min(best, (dx * dx + dy * dy).squareRoot())
                }
                #expect(abs(d[x, y] - best) < 1e-4, "at \(x), \(y)")
            }
        }
        let none = E.Distance.edt(seed: [UInt8](repeating: 0, count: 12), width: 4, height: 3, far: 99)
        #expect(none.pixels.allSatisfy { $0 == 99 })
    }

    @Test func fillCoversPixelCentresOutlineIncluded() {
        var m = [UInt8](repeating: 0, count: 100)
        let square: [SIMD2<Double>] = [SIMD2(2, 2), SIMD2(6, 2), SIMD2(6, 6), SIMD2(2, 6)]
        E.Polygon.fill(square, quarter: true, into: &m, width: 10, height: 10)
        #expect(m.reduce(0) { $0 + Int($1) } == 25, "pixels 2…6 both ways, as cv2.fillPoly draws them")
        // A big triangle: its count lies between its area and its area plus its outline.
        let tri: [SIMD2<Double>] = [SIMD2(3.25, 4.5), SIMD2(57.75, 9), SIMD2(20, 50.25)]
        var t = [UInt8](repeating: 0, count: 64 * 64)
        E.Polygon.fill(tri, quarter: true, into: &t, width: 64, height: 64)
        let n = Double(t.reduce(0) { $0 + Int($1) }), area = E.Polygon.area(tri)
        var perimeter = 0.0
        for i in 0..<3 { let v = tri[(i + 1) % 3] - tri[i]; perimeter += (v.x * v.x + v.y * v.y).squareRoot() }
        #expect(n >= area && n <= area + perimeter)
        // Clipped to the mask, never written outside it.
        var small = [UInt8](repeating: 0, count: 16)
        E.Polygon.fill([SIMD2(-5, -5), SIMD2(10, -5), SIMD2(10, 10), SIMD2(-5, 10)], quarter: false, into: &small, width: 4, height: 4)
        #expect(small.allSatisfy { $0 == 1 })
    }

    @Test func tracingRoundTripsAFilledPolygon() {
        let w = 48, h = 44
        let star: [SIMD2<Double>] = (0..<10).map { i in
            let a = Double(i) * .pi / 5, r = i % 2 == 0 ? 20.0 : 9.0
            return SIMD2(24 + r * cos(a), 22 + r * sin(a))
        }
        var m = [UInt8](repeating: 0, count: w * h)
        E.Polygon.fill(star, quarter: true, into: &m, width: w, height: h)
        var tracer = E.BorderTracer(m, width: w, height: h)
        let outline = tracer.first().map { SIMD2(Double($0.x), Double($0.y)) }
        #expect(outline.count > 40)
        var again = [UInt8](repeating: 0, count: w * h)
        E.Polygon.fill(outline, quarter: false, into: &again, width: w, height: h)
        #expect(again == m, "the border's polygon fills back to the same pixels")
        // Its area: the pixels less about half the border's.
        let count = Double(m.reduce(0) { $0 + Int($1) }), area = E.Polygon.area(outline)
        #expect(area < count && area > count - Double(outline.count))
        // Simplified, a square's border keeps its four corners.
        var sq = [UInt8](repeating: 0, count: 400)
        E.Polygon.fill([SIMD2(3, 4), SIMD2(15, 4), SIMD2(15, 14), SIMD2(3, 14)], quarter: false, into: &sq, width: 20, height: 20)
        var t2 = E.BorderTracer(sq, width: 20, height: 20)
        let corners = E.Polygon.simplify(closed: t2.first().map { SIMD2(Double($0.x), Double($0.y)) }, epsilon: 1.4)
        #expect(Set(corners.map { "\(Int($0.x)),\(Int($0.y))" }) == ["3,4", "15,4", "15,14", "3,14"])
    }

    @Test func listsEveryBorderHolesToo() {
        // A ring (one outer border, one hole) and a separate dot.
        let w = 30, h = 20
        var m = [UInt8](repeating: 0, count: w * h)
        for y in 2..<16 { for x in 2..<16 where !(y >= 6 && y < 12 && x >= 6 && x < 12) { m[y * w + x] = 1 } }
        m[5 * w + 24] = 1
        var tracer = E.BorderTracer(m, width: w, height: h)
        let rings = tracer.all()
        #expect(rings.count == 3)
        #expect(rings.contains { $0.count == 1 && $0[0] == SIMD2(24, 5) })
        let areas = rings.map { E.Polygon.area($0.map { SIMD2(Double($0.x), Double($0.y)) }) }.sorted()
        #expect(areas[2] == 13 * 13, "the outer border through the outer pixels' centres")
        #expect(areas[1] == 7 * 7 - 2, "the hole's border through the pixels beside it, its corners cut")
    }

    @Test func thinningLeavesOnePixelLines() {
        let w = 70, h = 40
        var m = [UInt8](repeating: 0, count: w * h)
        for y in 5..<14 { for x in 4..<64 { m[y * w + x] = 1 } }      // a bar 9 px thick
        for y in 5..<36 { for x in 50..<58 { m[y * w + x] = 1 } }     // and a leg: an L
        let s = E.Strokes.thin(m, width: w, height: h)
        let n = s.reduce(0) { $0 + Int($1) }
        #expect(n > 60 && n < 140)
        #expect(s.indices.allSatisfy { s[$0] == 0 || m[$0] == 1 }, "inside the shape")
        for y in 0..<(h - 1) {
            for x in 0..<(w - 1) {
                let block = s[y * w + x] & s[y * w + x + 1] & s[(y + 1) * w + x] & s[(y + 1) * w + x + 1]
                #expect(block == 0, "no 2×2 block at \(x), \(y)")
            }
        }
        #expect(E.Components.label(s, width: w, height: h, eight: true).sizes.count == 2, "still one piece")
        // Walked into chains: the L is three chains meeting at a node, or one bent one.
        let chains = E.Strokes.chains(s, width: w, height: h)
        #expect(!chains.isEmpty && chains.reduce(0) { $0 + $1.count } >= n)
    }

    @Test func kMeansIsDeterministicAndFindsClusters() {
        var rng = E.SplitMix64(seed: 11)
        let truth: [SIMD3<Float>] = [SIMD3(0.2, 0, 0), SIMD3(0.6, 0.1, -0.1), SIMD3(0.9, -0.1, 0.1)]
        var data: [SIMD3<Float>] = []
        for i in 0..<900 {
            let c = truth[i % 3]
            data.append(c + SIMD3(Float(rng.unit() - 0.5), Float(rng.unit() - 0.5), Float(rng.unit() - 0.5)) * 0.05)
        }
        var a = E.SplitMix64(seed: 5), b = E.SplitMix64(seed: 5)
        let r1 = E.KMeans.run(data, k: 3, maxIterations: 50, epsilon: 1e-5, attempts: 4, rng: &a)
        let r2 = E.KMeans.run(data, k: 3, maxIterations: 50, epsilon: 1e-5, attempts: 4, rng: &b)
        #expect(r1.centers == r2.centers && r1.compactness == r2.compactness)
        for t in truth {
            #expect(r1.centers.contains { E.KMeans.distance2($0, t) < 1e-3 })
        }
        // Fewer points than clusters: one centre a point.
        var c = E.SplitMix64(seed: 1)
        #expect(E.KMeans.run(Array(data.prefix(2)), k: 5, maxIterations: 5, epsilon: 0, attempts: 1, rng: &c).centers.count == 2)
        // The generator's sample: distinct, in range, repeatable.
        var s1 = E.SplitMix64(seed: 3), s2 = E.SplitMix64(seed: 3)
        let pick = s1.sample(1000, count: 100)
        #expect(Set(pick).count == 100 && pick.allSatisfy { $0 >= 0 && $0 < 1000 } && pick == s2.sample(1000, count: 100))
    }

    @Test func blursKeepTheirMassAndShape() {
        let k = E.Blur.kernel(sigma: 2)
        #expect(k.count == 17 && abs(k.reduce(0, +) - 1) < 1e-5)
        let flat = E.Plane(width: 31, height: 9, value: 0.4)
        #expect(E.Blur.gaussian(flat, sigma: 3).pixels.allSatisfy { abs($0 - 0.4) < 1e-5 })
        #expect(E.Blur.gaussian(flat, sigma: 12).pixels.allSatisfy { abs($0 - 0.4) < 1e-4 })
        // Three box blurs come within a few percent of the Gaussian on an impulse.
        var dot = E.Plane(width: 101, height: 101)
        dot[50, 50] = 1
        let exact = E.Plane(width: 101, height: 101, pixels: E.Blur.convolveColumns(
            E.Blur.convolveRows(dot.pixels, width: 101, height: 101, kernel: E.Blur.kernel(sigma: 8)),
            width: 101, height: 101, kernel: E.Blur.kernel(sigma: 8)))
        let boxed = E.Blur.boxGaussian(dot, sigma: 8)
        #expect(abs(boxed[50, 50] - exact[50, 50]) / exact[50, 50] < 0.08)
        #expect(abs(boxed[60, 50] - exact[60, 50]) / exact[60, 50] < 0.08)
        // The 2× bicubic keeps a flat image flat.
        #expect(E.Resize.upscale2x([Float](repeating: 0.3, count: 12), width: 4, height: 3).allSatisfy { abs($0 - 0.3) < 1e-5 })
    }

    @Test func filtersMatchTheirDefinitions() {
        var rng = E.SplitMix64(seed: 9)
        for (w, h, before, after) in [(19, 13, 3, 2), (41, 75, 15, 14), (9, 5, 15, 14)] {
            let p = E.Plane(width: w, height: h, pixels: (0..<(w * h)).map { _ in Float(rng.unit()) })
            let m = E.Morph.maxFilter(p, before: before, after: after)
            var wrong = 0
            for y in 0..<h {
                for x in 0..<w {
                    var best = -Float.infinity
                    for yy in max(y - before, 0)...min(y + after, h - 1) {
                        for xx in max(x - before, 0)...min(x + after, w - 1) { best = max(best, p[xx, yy]) }
                    }
                    if m[x, y] != best { wrong += 1 }
                }
            }
            #expect(wrong == 0, "\(w)×\(h), window −\(before)…+\(after)")
        }
        // The median of labels: a lone label in a field of another goes.
        var labels = [UInt8](repeating: 2, count: 15 * 15)
        labels[7 * 15 + 7] = 5
        #expect(E.Morph.median(labels, width: 15, height: 15, size: 9, levels: 8).allSatisfy { $0 == 2 })
        // Small pieces go, big ones stay.
        var mask = [UInt8](repeating: 0, count: 100)
        mask[11] = 1; mask[12] = 1
        for y in 4..<9 { for x in 3..<8 { mask[y * 10 + x] = 1 } }
        let kept = E.Components.removeSmall(mask, width: 10, height: 10, maxSize: 2)
        #expect(kept[11] == 0 && kept[12] == 0 && kept.reduce(0) { $0 + Int($1) } == 25)
        // The elliptical kernel OpenCV makes for a 2-pixel joint.
        #expect(E.Morph.ellipseRows(radius: 2) == [0, 2, 2, 2, 0])
    }

    @Test func pointInPolygonCountsTheEdgeAndIgnoresRepeatedCorners() {
        let ring: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10), SIMD2(10, 10), SIMD2(0, 10)]
        #expect(E.Polygon.contains(ring, SIMD2(5, 5)))
        #expect(E.Polygon.contains(ring, SIMD2(10, 4)), "on the edge")
        #expect(!E.Polygon.contains(ring, SIMD2(15, 5)))
        #expect(!E.Polygon.contains(ring, SIMD2(30, 30)), "a repeated corner is no edge everything lies on")
    }

    @Test func exactArithmeticMatchesTheLibrary() {
        for x in stride(from: -30.0, through: 30, by: 0.37) {
            #expect(abs(E.Exact.exp(x) - Foundation.exp(x)) <= 1e-14 * Foundation.exp(x))
            let (s, c) = E.Exact.sinCos(x)
            #expect(abs(s - Foundation.sin(x)) < 1e-14 && abs(c - Foundation.cos(x)) < 1e-14)
        }
        for x in [1e-9, 0.003, 0.25, 0.5, 0.7071, 1, 1.4142, 2, 10, 12345.678] {
            #expect(abs(E.Exact.log(x) - Foundation.log(x)) < 1e-14 * max(1, abs(Foundation.log(x))))
            #expect(abs(E.Exact.cbrt(x) - Foundation.cbrt(x)) < 1e-15 * Foundation.cbrt(x) * 4)
            #expect(abs(Double(E.Exact.cbrt(Float(x))) - Foundation.cbrt(Double(Float(x)))) < 1e-6 * Foundation.cbrt(x))
            #expect(abs(E.Exact.pow(x, 2.4) - Foundation.pow(x, 2.4)) < 1e-13 * Foundation.pow(x, 2.4))
        }
        #expect(E.Exact.exp(-800) == 0 && E.Exact.cbrt(-8.0) == -2 && E.Exact.cbrt(Float(0)) == 0)
        // OKLab both ways, exactly and by the tables.
        let fast = E.FastOKLab()
        for c in [SIMD3<Float>(0.8, 0.15, 0.1), SIMD3(0.15, 0.25, 0.75), SIMD3(0.5, 0.5, 0.5), SIMD3(1, 1, 1), SIMD3(0.02, 0.9, 0.3)] {
            let lab = E.Colour.lab(c)
            #expect(apart(E.Colour.rgb(lab), c) < 1e-5)
            #expect(apart(fast.lab(c), lab) < 2e-3)
            #expect(apart(fast.rgb(lab), c) < 3e-3)
        }
        #expect(abs(E.Colour.lab(SIMD3(1, 1, 1)).x - 1) < 1e-4)
    }
}

/// The largest difference between two colours' components.
private func apart(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d = a - b
    return max(abs(d.x), abs(d.y), abs(d.z))
}
