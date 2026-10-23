nonisolated extension MosaicEngine {
    /// How a face's mouth is set (issue #1's weakest feature, an option until Paul narrows it): as
    /// the photo has it (a smile and its teeth, laid as they are), or the Byzantine way, small, fine
    /// and closed, the upper lip narrower than the lower and the lower lip lightened (icon painters'
    /// practice: Atelier saint André, "Byzantine style",
    /// https://atelier-st-andre.net/en/pages/aesthetics/byzantine_style.html). Closed is this
    /// engine's reading of the calm those faces keep, not a rule from a source.
    nonisolated public enum Mouth: String, Sendable, Equatable, CaseIterable {
        case asInThePhoto, byzantine
    }

    /// Each face's mouth redrawn the Byzantine way, before the run: in the photo the old mouth is
    /// filled with the skin round it and the new lips painted in, shaded, from the photo's upper lip;
    /// the contours under the old mouth are cleared; the mouth's lines become the new mouth's. A
    /// face without a lips outline (a pet's) is left as it is. Exact arithmetic only (`+ - * /`,
    /// `sqrt`), so the result is the same on every machine.
    static func byzantineMouths(_ photo: inout Photo, _ contours: inout [Float], _ faces: inout [Face]) {
        for f in faces.indices {
            guard let lips = faces[f].lines.first(where: { $0.kind == "lips" }) else { continue }
            let old = lips.pts.filter { $0.count >= 2 }.map { SIMD2(Double($0[0]), Double($0[1])) }
            guard old.count >= 4 else { continue }
            let xs = old.map(\.x), ys = old.map(\.y)
            let lo = SIMD2(xs.min()!, ys.min()!), hi = SIMD2(xs.max()!, ys.max()!)
            let span = hi - lo, near = (lo - 0.25 * span.x, hi + 0.25 * span.x)
            func isMouth(_ line: Face.Line) -> Bool {
                guard line.kind == "lips" || line.kind == "tone" || line.kind == "dark" else { return false }
                let p = line.pts.filter { $0.count >= 2 }
                guard !p.isEmpty else { return false }
                let c = p.reduce(SIMD2<Double>.zero) { $0 + SIMD2(Double($1[0]), Double($1[1])) } / Double(p.count)
                return c.x >= near.0.x && c.x <= near.1.x && c.y >= near.0.y && c.y <= near.1.y
            }
            // The mouth's frame: u along it from corner to corner, v across it, down the face.
            let left = old.min { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }!
            let right = old.max { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }!
            let width = ((right - left) * (right - left)).sum().squareRoot()
            guard width > 2 else { continue }
            let a = (right - left) / width, n = SIMD2(-a.y, a.x), c0 = (left + right) / 2
            func v(_ p: SIMD2<Double>) -> Double { ((p - c0) * n).sum() }
            let vs = old.map(v), top = vs.min()!, bottom = vs.max()!
            let meeting = faces[f].lines.first { $0.kind == "dark" && isMouth($0) }
                .map { l -> Double in
                    let p = l.pts[l.pts.count / 2]
                    return v(SIMD2(Double(p[0]), Double(p[1])))
                } ?? (top + bottom) / 2

            // The new mouth: 0.8 of the width, as tall as a closed mouth that wide (no taller than the
            // photo's), the lips meeting where the photo's upper lip ends.
            let w = 0.8 * width, h = Swift.min(0.36 * w, bottom - top)
            let upper = 0.4 * h, lower = 0.6 * h
            let vm = Swift.min(Swift.max(meeting, top + upper), bottom - lower)
            func at(_ u: Double, _ v: Double) -> SIMD2<Double> { c0 + u * a + v * n }
            let steps = 10
            var meet: [SIMD2<Double>] = [], top2: [SIMD2<Double>] = [], bottom2: [SIMD2<Double>] = []
            for i in 0...steps {
                let s = 2 * Double(i) / Double(steps) - 1, u = s * w / 2
                let droop = 0.06 * h * s * s, bulge = 1 - s * s
                meet.append(at(u, vm + droop))
                top2.append(at(u, vm + droop - upper * bulge))
                bottom2.append(at(u, vm + droop + lower * bulge))
            }
            let upperLip = top2 + meet.reversed(), lowerLip = meet + bottom2.reversed()
            let outline = top2 + Array(bottom2.reversed().dropFirst().dropLast())

            // The pixels to repaint: the old mouth and a margin round it (its shadow and edge).
            let pad = 0.1 * width
            let W = photo.width, H = photo.height
            let x0 = Swift.max(Int(lo.x - pad) - 1, 1), x1 = Swift.min(Int(hi.x + pad) + 2, W - 2)
            let y0 = Swift.max(Int(lo.y - pad) - 1, 1), y1 = Swift.min(Int(hi.y + pad) + 2, H - 2)
            guard x1 > x0, y1 > y0 else { continue }
            var mask = [Bool](repeating: false, count: W * H)
            var lipPixels: [SIMD3<Float>] = []
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                    var d = Double.infinity
                    for i in old.indices { d = Swift.min(d, Polygon.segmentDistance(p, old[i], old[(i + 1) % old.count])) }
                    let inOld = Polygon.contains(old, p)
                    if inOld || d <= pad { mask[y * W + x] = true }
                    if inOld && v(p) < meeting { lipPixels.append(photo.rgb[y * W + x]) }
                }
            }
            // The skin: each masked pixel first the blend of the nearest unmasked pixels above and
            // below it, then smoothed with its neighbours (Gauss-Seidel, in raster order).
            for x in x0...x1 {
                var y = y0
                while y <= y1 {
                    guard mask[y * W + x] else { y += 1; continue }
                    var e = y
                    while e + 1 < H && mask[(e + 1) * W + x] { e += 1 }
                    let above = photo.rgb[(y - 1) * W + x], below = photo.rgb[Swift.min(e + 1, H - 1) * W + x]
                    for k in y...e {
                        let t = Float(k - y + 1) / Float(e - y + 2)
                        photo.rgb[k * W + x] = above * (1 - t) + below * t
                    }
                    y = e + 1
                }
            }
            for _ in 0..<60 {
                for y in y0...y1 {
                    for x in x0...x1 where mask[y * W + x] {
                        let i = y * W + x
                        photo.rgb[i] = (photo.rgb[i - 1] + photo.rgb[i + 1] + photo.rgb[i - W] + photo.rgb[i + W]) * 0.25
                    }
                }
            }
            for y in y0...y1 { for x in x0...x1 where mask[y * W + x] { contours[y * W + x] = 0 } }
            // The lips' red: the more coloured half of the photo's upper lip (its outline takes in skin).
            func chroma(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }
            let ranked = lipPixels.indices.sorted { chroma(lipPixels[$0]) != chroma(lipPixels[$1]) ? chroma(lipPixels[$0]) > chroma(lipPixels[$1]) : $0 < $1 }
            let half = ranked.prefix(Swift.max(ranked.count / 2, 1))
            let red = lipPixels.isEmpty ? SIMD3<Float>(0.6, 0.3, 0.3) : half.reduce(SIMD3<Float>.zero) { $0 + lipPixels[$1] } / Float(half.count)
            // Each lip in two tones, so its rows differ as a mosaicist's do and each tone can earn its
            // own paint: the upper deeper along the line where the lips meet, the lower lit across its middle.
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                    let s = Swift.min(Swift.max(2 * ((p - c0) * a).sum() / w, -1), 1), bulge = Swift.max(1 - s * s, 0.05)
                    let below = v(p) - (vm + 0.06 * h * s * s)
                    if Polygon.contains(upperLip, p) {
                        let t = Float(Swift.min(Swift.max(-below / (upper * bulge), 0), 1))
                        photo.rgb[y * W + x] = red * (t < 0.5 ? 0.8 : 0.96)
                    } else if Polygon.contains(lowerLip, p) {
                        let t = Float(Swift.min(Swift.max(below / (lower * bulge), 0), 1))
                        photo.rgb[y * W + x] = pointwiseMin(red * (t > 0.25 && t < 0.7 ? 1.18 : 1.02), SIMD3(repeating: 1))
                    }
                }
            }

            // The mouth's lines, the new mouth's, where the old ones were in the list.
            func line(_ kind: String, _ p: [SIMD2<Double>]) -> Face.Line { .init(kind: kind, pts: p.map { [Float($0.x), Float($0.y)] }) }
            let new = [line("tone", top2), line("tone", bottom2), line("lips", outline), line("dark", meet)]
            let at0 = faces[f].lines.firstIndex(where: isMouth) ?? faces[f].lines.count
            let kept = faces[f].lines.enumerated().filter { !isMouth($0.element) }
            let before = kept.filter { $0.offset < at0 }.map(\.element), after = kept.filter { $0.offset > at0 }.map(\.element)
            faces[f].lines = before + new + after
        }
    }
}
