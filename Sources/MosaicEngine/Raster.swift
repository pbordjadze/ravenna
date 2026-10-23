nonisolated extension MosaicEngine {
    // The image primitives the prototype took from OpenCV and SciPy, in plain Swift: blurs, resizes,
    // morphology, distance transforms and filters over row-major rasters. Bit-exact parity with those
    // libraries isn't the aim; the same behaviour at the borders and the same kernels are.

    /// A float raster, row-major.
    nonisolated struct Plane: Sendable, Equatable {
        var width: Int
        var height: Int
        var pixels: [Float]

        init(width: Int, height: Int, value: Float = 0) {
            self.width = width; self.height = height
            pixels = [Float](repeating: value, count: width * height)
        }

        init(width: Int, height: Int, pixels: [Float]) {
            precondition(pixels.count == width * height, "a plane's pixels are width × height")
            self.width = width; self.height = height; self.pixels = pixels
        }

        @inline(__always) subscript(x: Int, y: Int) -> Float {
            get { pixels[y * width + x] }
            set { pixels[y * width + x] = newValue }
        }

        var max: Float { pixels.max() ?? 0 }
    }

    /// SciPy's `reflect` border (d c b a | a b c d | d c b a), for any index.
    @inline(__always) static func reflectIndex(_ i: Int, _ n: Int) -> Int {
        if n <= 1 { return 0 }
        let period = 2 * n
        var m = i % period
        if m < 0 { m += period }
        return m < n ? m : period - 1 - m
    }

    @inline(__always) static func clampIndex(_ i: Int, _ n: Int) -> Int { i < 0 ? 0 : (i >= n ? n - 1 : i) }

    nonisolated enum Blur {
        /// SciPy's Gaussian kernel: radius `int(4σ + 0.5)`, normalised.
        static func kernel(sigma: Double) -> [Float] {
            let r = Int(4 * sigma + 0.5)
            var w = [Double](repeating: 0, count: 2 * r + 1)
            var sum = 0.0
            for i in -r...r {
                let v = Exact.exp(-0.5 * Double(i * i) / (sigma * sigma))
                w[i + r] = v; sum += v
            }
            return w.map { Float($0 / sum) }
        }

        /// `scipy.ndimage.gaussian_filter` (reflect border). Large sigmas go through three box blurs,
        /// which match a Gaussian to within a percent or two at a fraction of the cost.
        static func gaussian(_ p: Plane, sigma: Double) -> Plane {
            guard sigma > 0, p.width > 0, p.height > 0 else { return p }
            if sigma > 5 { return boxGaussian(p, sigma: sigma) }
            let k = kernel(sigma: sigma)
            let h = convolveRows(p.pixels, width: p.width, height: p.height, kernel: k)
            return Plane(width: p.width, height: p.height,
                         pixels: convolveColumns(h, width: p.width, height: p.height, kernel: k))
        }

        static func convolveRows(_ src: [Float], width w: Int, height h: Int, kernel k: [Float]) -> [Float] {
            let r = k.count / 2, n = w + 2 * r
            var out = [Float](repeating: 0, count: w * h)
            let index = (0..<n).map { reflectIndex($0 - r, w) }
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    index.withUnsafeBufferPointer { ix in
                        k.withUnsafeBufferPointer { kk in
                            let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o)
                            let ix = Parallel.Unchecked(ix), kk = Parallel.Unchecked(kk)
                            Parallel.ranges(h, grain: 16) { rows in
                                var line = [Float](repeating: 0, count: n)
                                line.withUnsafeMutableBufferPointer { l in
                                    for y in rows {
                                        let row = y * w
                                        for i in 0..<n { l[i] = s.value[row + ix.value[i]] }
                                        let dst = o.value.baseAddress! + row
                                        for x in 0..<w { dst[x] = 0 }
                                        for j in 0..<kk.value.count {
                                            let wj = kk.value[j], src = l.baseAddress! + j
                                            for x in 0..<w { dst[x] += wj * src[x] }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return out
        }

        static func convolveColumns(_ src: [Float], width w: Int, height h: Int, kernel k: [Float]) -> [Float] {
            let r = k.count / 2
            var out = [Float](repeating: 0, count: w * h)
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    k.withUnsafeBufferPointer { kk in
                        let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o), kk = Parallel.Unchecked(kk)
                        Parallel.ranges(h, grain: 16) { rows in
                            for y in rows {
                                let dst = o.value.baseAddress! + y * w
                                for j in 0..<kk.value.count {
                                    let wj = kk.value[j], row = s.value.baseAddress! + reflectIndex(y + j - r, h) * w
                                    for x in 0..<w { dst[x] += wj * row[x] }
                                }
                            }
                        }
                    }
                }
            }
            return out
        }

        /// The widths of three box blurs whose sum approximates a Gaussian (Kovesi's construction).
        static func boxWidths(sigma: Double, passes n: Int = 3) -> [Int] {
            let ideal = (12 * sigma * sigma / Double(n) + 1).squareRoot()
            var wl = Int(ideal)
            if wl % 2 == 0 { wl -= 1 }
            wl = Swift.max(wl, 1)
            let wu = wl + 2
            let mIdeal = (12 * sigma * sigma - Double(n * wl * wl + 4 * n * wl + 3 * n)) / Double(-4 * wl - 4)
            let m = Int(mIdeal.rounded())
            return (0..<n).map { $0 < m ? wl : wu }
        }

        static func boxGaussian(_ p: Plane, sigma: Double) -> Plane {
            var px = p.pixels
            for width in boxWidths(sigma: sigma) {
                let r = (width - 1) / 2
                guard r > 0 else { continue }
                px = boxRows(px, width: p.width, height: p.height, radius: r)
                px = boxColumns(px, width: p.width, height: p.height, radius: r)
            }
            return Plane(width: p.width, height: p.height, pixels: px)
        }

        static func boxRows(_ src: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
            let n = w + 2 * r, inv = 1 / Double(2 * r + 1)
            var out = [Float](repeating: 0, count: w * h)
            let index = (0..<n).map { reflectIndex($0 - r, w) }
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    index.withUnsafeBufferPointer { ix in
                        let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o), ix = Parallel.Unchecked(ix)
                        Parallel.ranges(h, grain: 16) { rows in
                            var line = [Double](repeating: 0, count: n)
                            line.withUnsafeMutableBufferPointer { l in
                                for y in rows {
                                    let row = y * w
                                    for i in 0..<n { l[i] = Double(s.value[row + ix.value[i]]) }
                                    var sum = 0.0
                                    for i in 0...(2 * r) { sum += l[i] }
                                    o.value[row] = Float(sum * inv)
                                    if w > 1 {
                                        for x in 1..<w {
                                            sum += l[x + 2 * r] - l[x - 1]
                                            o.value[row + x] = Float(sum * inv)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return out
        }

        static func boxColumns(_ src: [Float], width w: Int, height h: Int, radius r: Int) -> [Float] {
            let inv = 1 / Double(2 * r + 1)
            var out = [Float](repeating: 0, count: w * h)
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o)
                    // In strips of columns, each with its own running sums.
                    Parallel.ranges(w, grain: 256) { cols in
                        let x0 = cols.lowerBound, n = cols.count
                        var acc = [Double](repeating: 0, count: n)
                        acc.withUnsafeMutableBufferPointer { a in
                            for j in -r...r {
                                let row = s.value.baseAddress! + reflectIndex(j, h) * w + x0
                                for x in 0..<n { a[x] += Double(row[x]) }
                            }
                            for y in 0..<h {
                                if y > 0 {
                                    let add = s.value.baseAddress! + reflectIndex(y + r, h) * w + x0
                                    let sub = s.value.baseAddress! + reflectIndex(y - r - 1, h) * w + x0
                                    for x in 0..<n { a[x] += Double(add[x]) - Double(sub[x]) }
                                }
                                let dst = o.value.baseAddress! + y * w + x0
                                for x in 0..<n { dst[x] = Float(a[x] * inv) }
                            }
                        }
                    }
                }
            }
            return out
        }

        /// `scipy.ndimage.gaussian_filter1d` along a polyline's coordinates, `nearest` border (open
        /// lines) or `wrap` (rings).
        static func smooth(_ pts: [SIMD2<Double>], sigma: Double, wrap: Bool) -> [SIMD2<Double>] {
            let n = pts.count
            guard n > 1, sigma > 0 else { return pts }
            let r = Int(4 * sigma + 0.5)
            var w = [Double](repeating: 0, count: 2 * r + 1), sum = 0.0
            for i in -r...r { let v = Exact.exp(-0.5 * Double(i * i) / (sigma * sigma)); w[i + r] = v; sum += v }
            for i in w.indices { w[i] /= sum }
            var out = [SIMD2<Double>](repeating: .zero, count: n)
            for i in 0..<n {
                var acc = SIMD2<Double>.zero
                for j in -r...r {
                    var k = i + j
                    if wrap { k %= n; if k < 0 { k += n } } else { k = clampIndex(k, n) }
                    acc += w[j + r] * pts[k]
                }
                out[i] = acc
            }
            return out
        }
    }

    nonisolated enum Resize {
        /// OpenCV's bicubic weights (A = −0.75) for a fractional offset.
        static func cubic(_ x: Float) -> SIMD4<Float> {
            let a: Float = -0.75
            let c0 = ((a * (x + 1) - 5 * a) * (x + 1) + 8 * a) * (x + 1) - 4 * a
            let c1 = ((a + 2) * x - (a + 3)) * x * x + 1
            let c2 = ((a + 2) * (1 - x) - (a + 3)) * (1 - x) * (1 - x) + 1
            return SIMD4(c0, c1, c2, 1 - c0 - c1 - c2)
        }

        /// `cv2.resize(…, 2×, INTER_CUBIC)`: half-pixel centres, the border replicated.
        static func upscale2x(_ src: [Float], width w: Int, height h: Int) -> [Float] {
            let W = 2 * w, H = 2 * h
            let even = cubic(0.75), odd = cubic(0.25)
            // Rows: w → W.
            var mid = [Float](repeating: 0, count: W * h)
            src.withUnsafeBufferPointer { s in
                mid.withUnsafeMutableBufferPointer { m in
                    let s = Parallel.Unchecked(s), m = Parallel.Unchecked(m)
                    Parallel.ranges(h, grain: 16) { rows in
                        for y in rows {
                            let row = s.value.baseAddress! + y * w, dst = m.value.baseAddress! + y * W
                            for i in 0..<w {
                                let a = row[clampIndex(i - 2, w)], b = row[clampIndex(i - 1, w)], c = row[i]
                                let d = row[clampIndex(i + 1, w)], e = row[clampIndex(i + 2, w)]
                                dst[2 * i] = even.x * a + even.y * b + even.z * c + even.w * d
                                dst[2 * i + 1] = odd.x * b + odd.y * c + odd.z * d + odd.w * e
                            }
                        }
                    }
                }
            }
            // Columns: h → H.
            var out = [Float](repeating: 0, count: W * H)
            mid.withUnsafeBufferPointer { m in
                out.withUnsafeMutableBufferPointer { o in
                    let m = Parallel.Unchecked(m.baseAddress!), o = Parallel.Unchecked(o)
                    Parallel.ranges(h, grain: 8) { rows in
                        for i in rows {
                            let a = m.value + clampIndex(i - 2, h) * W, b = m.value + clampIndex(i - 1, h) * W
                            let c = m.value + i * W
                            let d = m.value + clampIndex(i + 1, h) * W, e = m.value + clampIndex(i + 2, h) * W
                            let r0 = o.value.baseAddress! + 2 * i * W, r1 = r0 + W
                            for x in 0..<W {
                                r0[x] = even.x * a[x] + even.y * b[x] + even.z * c[x] + even.w * d[x]
                                r1[x] = odd.x * b[x] + odd.y * c[x] + odd.z * d[x] + odd.w * e[x]
                            }
                        }
                    }
                }
            }
            return out
        }

        /// `cv2.resize(…, INTER_LINEAR)` to any size: half-pixel centres, the border replicated.
        static func bilinear(_ src: [Float], width w: Int, height h: Int, to W: Int, _ H: Int) -> [Float] {
            if w == W && h == H { return src }
            func taps(_ n: Int, _ N: Int) -> [(Int, Int, Float)] {
                let scale = Double(n) / Double(N)
                return (0..<N).map { d in
                    let f = (Double(d) + 0.5) * scale - 0.5
                    var s = Int(f.rounded(.down)), t = Float(f - Double(s))
                    if s < 0 { s = 0; t = 0 }
                    if s >= n - 1 { s = n - 1; t = 0 }
                    return (s, Swift.min(s + 1, n - 1), t)
                }
            }
            let xs = taps(w, W), ys = taps(h, H)
            var out = [Float](repeating: 0, count: W * H)
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o)
                    Parallel.ranges(H, grain: 16) { rows in
                        for y in rows {
                            let (y0, y1, ty) = ys[y]
                            for x in 0..<W {
                                let (x0, x1, tx) = xs[x]
                                let top = s.value[y0 * w + x0] * (1 - tx) + s.value[y0 * w + x1] * tx
                                let bottom = s.value[y1 * w + x0] * (1 - tx) + s.value[y1 * w + x1] * tx
                                o.value[y * W + x] = top * (1 - ty) + bottom * ty
                            }
                        }
                    }
                }
            }
            return out
        }
    }

    nonisolated enum Morph {
        /// Dilation (`max`) or erosion (`min`) of a binary mask by a (2r+1)² square, pixels outside the
        /// image ignored, as OpenCV's morphology treats its default border.
        static func rect(_ m: [UInt8], width w: Int, height h: Int, radius r: Int, dilate: Bool) -> [UInt8] {
            var tmp = [UInt8](repeating: 0, count: w * h), out = tmp
            let hit: UInt8 = dilate ? 1 : 0
            m.withUnsafeBufferPointer { s in
                tmp.withUnsafeMutableBufferPointer { t in
                    let s = Parallel.Unchecked(s), t = Parallel.Unchecked(t)
                    Parallel.ranges(h, grain: 16) { rows in
                        for y in rows {
                            let row = y * w
                            for x in 0..<w {
                                var v: UInt8 = dilate ? 0 : 1
                                for k in Swift.max(x - r, 0)...Swift.min(x + r, w - 1) where (s.value[row + k] != 0) == dilate {
                                    v = hit; break
                                }
                                t.value[row + x] = v
                            }
                        }
                    }
                }
            }
            tmp.withUnsafeBufferPointer { t in
                out.withUnsafeMutableBufferPointer { o in
                    let t = Parallel.Unchecked(t), o = Parallel.Unchecked(o)
                    Parallel.ranges(h, grain: 16) { rows in
                        for y in rows {
                            for x in 0..<w {
                                var v: UInt8 = dilate ? 0 : 1
                                for k in Swift.max(y - r, 0)...Swift.min(y + r, h - 1) where (t.value[k * w + x] != 0) == dilate {
                                    v = hit; break
                                }
                                o.value[y * w + x] = v
                            }
                        }
                    }
                }
            }
            return out
        }

        /// `MORPH_CLOSE` with a (2r+1)² square.
        static func close(_ m: [UInt8], width w: Int, height h: Int, radius r: Int) -> [UInt8] {
            rect(rect(m, width: w, height: h, radius: r, dilate: true), width: w, height: h, radius: r, dilate: false)
        }

        /// `cv2.getStructuringElement(MORPH_ELLIPSE, (2r+1, 2r+1))` as the half-width of each row, top to bottom.
        static func ellipseRows(radius r: Int) -> [Int] {
            guard r > 0 else { return [0] }
            let inv = 1 / Double(r * r)
            return (0...(2 * r)).map { i in
                let dy = i - r
                return Int((Double(r) * (Double(r * r - dy * dy) * inv).squareRoot()).rounded(.toNearestOrEven))
            }
        }

        /// A 3×3 morphological gradient of a label image: whether any neighbour in the image differs.
        static func labelEdges(_ labels: [UInt8], width w: Int, height h: Int) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: w * h)
            labels.withUnsafeBufferPointer { l in
                out.withUnsafeMutableBufferPointer { o in
                    let l = Parallel.Unchecked(l), o = Parallel.Unchecked(o)
                    Parallel.ranges(h, grain: 16) { rows in
                        for y in rows {
                            let y0 = Swift.max(y - 1, 0), y1 = Swift.min(y + 1, h - 1)
                            for x in 0..<w {
                                let v = l.value[y * w + x]
                                let x0 = Swift.max(x - 1, 0), x1 = Swift.min(x + 1, w - 1)
                                var edge: UInt8 = 0
                                outer: for yy in y0...y1 {
                                    for xx in x0...x1 where l.value[yy * w + xx] != v { edge = 1; break outer }
                                }
                                o.value[y * w + x] = edge
                            }
                        }
                    }
                }
            }
            return out
        }

        /// `cv2.medianBlur(labels, k)` for small label values (all under `levels`), the border replicated:
        /// a sliding histogram along each row.
        static func median(_ labels: [UInt8], width w: Int, height h: Int, size k: Int, levels: Int) -> [UInt8] {
            let r = k / 2, half = (k * k) / 2
            var out = [UInt8](repeating: 0, count: w * h)
            let bins = Swift.max(levels, 1)
            labels.withUnsafeBufferPointer { l in
                out.withUnsafeMutableBufferPointer { o in
                    let l = Parallel.Unchecked(l), o = Parallel.Unchecked(o)
                    Parallel.ranges(h, grain: 16) { band in
                        var hist = [Int](repeating: 0, count: bins), rows = [Int](repeating: 0, count: 2 * r + 1)
                        hist.withUnsafeMutableBufferPointer { hs in
                            for y in band {
                                for b in 0..<bins { hs[b] = 0 }
                                for j in 0...(2 * r) { rows[j] = clampIndex(y + j - r, h) * w }
                                for dx in -r...r {
                                    let xx = clampIndex(dx, w)
                                    for row in rows { hs[Int(l.value[row + xx])] += 1 }
                                }
                                for x in 0..<w {
                                    if x > 0 {
                                        let add = clampIndex(x + r, w), sub = clampIndex(x - r - 1, w)
                                        for row in rows { hs[Int(l.value[row + add])] += 1; hs[Int(l.value[row + sub])] -= 1 }
                                    }
                                    var c = 0, v = 0
                                    while v < bins { c += hs[v]; if c > half { break }; v += 1 }
                                    o.value[y * w + x] = UInt8(Swift.min(v, bins - 1))
                                }
                            }
                        }
                    }
                }
            }
            return out
        }

        /// A blocked transpose of a row-major raster.
        static func transpose<T>(_ src: [T], width w: Int, height h: Int, zero: T) -> [T] {
            var out = [T](repeating: zero, count: w * h)
            let b = 32
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    var y0 = 0
                    while y0 < h {
                        var x0 = 0
                        while x0 < w {
                            for y in y0..<Swift.min(y0 + b, h) {
                                for x in x0..<Swift.min(x0 + b, w) { o[x * h + y] = s[y * w + x] }
                            }
                            x0 += b
                        }
                        y0 += b
                    }
                }
            }
            return out
        }

        /// The maximum over a window [x − before, x + after] × [y − before, y + after] clipped to the
        /// image: `cv2.dilate(src, np.ones((k, k)))` with its anchor at k/2 (before = k/2, after = k − 1 − k/2).
        static func maxFilter(_ p: Plane, before: Int, after: Int) -> Plane {
            let w = p.width, h = p.height
            let rows = slidingMaxRows(p.pixels, width: w, height: h, before: before, after: after)
            return Plane(width: w, height: h, pixels: slidingMaxColumns(consume rows, width: w, height: h, before: before, after: after))
        }

        /// The column pass of `maxFilter`, row by row (van Herk and Gil-Werman): blocks of the window's
        /// height, each with its running maxima down from its top and up from its bottom; a window
        /// spans at most two blocks, so its maximum is the first's from below and the second's from above.
        /// The maxima go into the running maxima from above as they're made (a row's window ends at
        /// or below it, and that row isn't overwritten yet), so it takes two planes, `src` among them.
        static func slidingMaxColumns(_ src: consuming [Float], width w: Int, height h: Int, before: Int, after: Int) -> [Float] {
            let k = before + after + 1
            guard k > 1, h > 1 else { return src }
            var up = src
            var down = up
            down.withUnsafeMutableBufferPointer { dn in
                up.withUnsafeMutableBufferPointer { u in
                    let dn = Parallel.Unchecked(dn.baseAddress!), u = Parallel.Unchecked(u.baseAddress!)
                    // In strips of columns, each strip's rows in order.
                    Parallel.ranges(w, grain: 256) { cols in
                        let x0 = cols.lowerBound, n = cols.count
                        for y in 0..<h where y % k != 0 {
                            let cur = dn.value + y * w + x0, prev = dn.value + (y - 1) * w + x0
                            for x in 0..<n { cur[x] = Swift.max(cur[x], prev[x]) }
                        }
                        for y in stride(from: h - 2, through: 0, by: -1) where (y + 1) % k != 0 {
                            let cur = u.value + y * w + x0, next = u.value + (y + 1) * w + x0
                            for x in 0..<n { cur[x] = Swift.max(cur[x], next[x]) }
                        }
                        for y in 0..<h {
                            let a = Swift.max(y - before, 0), b = Swift.min(y + after, h - 1)
                            let dst = dn.value + y * w + x0
                            let fromA = UnsafePointer(u.value + a * w + x0), toB = UnsafePointer(dn.value + b * w + x0)
                            if a / k != b / k {
                                for x in 0..<n { dst[x] = Swift.max(fromA[x], toB[x]) }
                            } else if b == h - 1 || (b + 1) % k == 0 {
                                // One block, the window reaching its end (clipped at the image's bottom).
                                for x in 0..<n { dst[x] = fromA[x] }
                            } else {
                                // One block, the window from its start (clipped at the image's top).
                                for x in 0..<n { dst[x] = toB[x] }
                            }
                        }
                    }
                }
            }
            return down
        }

        static func slidingMaxRows(_ src: [Float], width w: Int, height h: Int, before: Int, after: Int) -> [Float] {
            var out = [Float](repeating: 0, count: w * h)
            src.withUnsafeBufferPointer { s in
                out.withUnsafeMutableBufferPointer { o in
                    let s = Parallel.Unchecked(s), o = Parallel.Unchecked(o)
                    Parallel.ranges(h, grain: 16) { band in
                        var dq = [Int](repeating: 0, count: w)
                        dq.withUnsafeMutableBufferPointer { q in
                            for y in band {
                                let row = s.value.baseAddress! + y * w, dst = o.value.baseAddress! + y * w
                                var head = 0, tail = 0, j = 0
                                for i in 0..<w {
                                    let right = Swift.min(i + after, w - 1)
                                    while j <= right {
                                        let v = row[j]
                                        while tail > head && row[q[tail - 1]] <= v { tail -= 1 }
                                        q[tail] = j; tail += 1; j += 1
                                    }
                                    while q[head] < i - before { head += 1 }
                                    dst[i] = row[q[head]]
                                }
                            }
                        }
                    }
                }
            }
            return out
        }
    }

    nonisolated enum Distance {
        /// The exact Euclidean distance from each pixel to the nearest pixel where `seed` is set
        /// (Felzenszwalb and Huttenlocher, 2012): `distance_transform_edt(~seed)`. Without any seed
        /// every distance is `far`.
        static func edt(seed: [UInt8], width w: Int, height h: Int, far: Float = 1e9) -> Plane {
            let inf: Float = 1e20
            // Down each column: the 1D distance to the nearest seed, squared. In strips of columns, row
            // by row, each column remembering its last seed, so the passes run along memory.
            var g = [Float](repeating: inf, count: w * h)
            seed.withUnsafeBufferPointer { s in
                g.withUnsafeMutableBufferPointer { gg in
                    let s = Parallel.Unchecked(s), gg = Parallel.Unchecked(gg)
                    Parallel.ranges(w, grain: 256) { cols in
                        let x0 = cols.lowerBound, n = cols.count
                        var last = [Int](repeating: -1, count: n)
                        last.withUnsafeMutableBufferPointer { l in
                            for y in 0..<h {
                                let row = y * w + x0
                                for x in 0..<n {
                                    if s.value[row + x] != 0 { l[x] = y }
                                    if l[x] >= 0 { let d = Float(y - l[x]); gg.value[row + x] = d * d }
                                }
                            }
                            for x in 0..<n { l[x] = -1 }
                            for y in stride(from: h - 1, through: 0, by: -1) {
                                let row = y * w + x0
                                for x in 0..<n {
                                    if s.value[row + x] != 0 { l[x] = y }
                                    if l[x] >= 0 { let d = Float(l[x] - y); gg.value[row + x] = Swift.min(gg.value[row + x], d * d) }
                                }
                            }
                        }
                    }
                }
            }
            // Along rows: the lower envelope of parabolas, each row's distances written over its own.
            g.withUnsafeMutableBufferPointer { o in
                let o = Parallel.Unchecked(o)
                Parallel.ranges(h, grain: 16) { rows in
                    var f = [Double](repeating: 0, count: w), d = f
                    var v = [Int](repeating: 0, count: w), z = [Double](repeating: 0, count: w + 1)
                    for y in rows {
                        let row = y * w
                        for x in 0..<w { f[x] = Double(o.value[row + x]) }
                        f.withUnsafeBufferPointer { ff in
                            d.withUnsafeMutableBufferPointer { dd in
                                lowerEnvelope(ff.baseAddress!, count: w, out: dd.baseAddress!, v: &v, z: &z)
                            }
                        }
                        for x in 0..<w { o.value[row + x] = d[x] >= 1e19 ? far : Float(d[x].squareRoot()) }
                    }
                }
            }
            return Plane(width: w, height: h, pixels: g)
        }

        static func lowerEnvelope(_ f: UnsafePointer<Double>, count n: Int, out: UnsafeMutablePointer<Double>,
                                  v: inout [Int], z: inout [Double]) {
            guard n > 0 else { return }
            var k = 0
            v[0] = 0; z[0] = -.infinity; z[1] = .infinity
            if n > 1 {
                for q in 1..<n {
                    let fq = f[q] + Double(q * q)
                    var s = (fq - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                    while s <= z[k] {   // z[0] is −∞, so k never drops below 0
                        k -= 1
                        s = (fq - (f[v[k]] + Double(v[k] * v[k]))) / Double(2 * q - 2 * v[k])
                    }
                    k += 1
                    v[k] = q; z[k] = s; z[k + 1] = .infinity
                }
            }
            k = 0
            for q in 0..<n {
                while z[k + 1] < Double(q) { k += 1 }
                let dq = Double(q - v[k])
                out[q] = dq * dq + f[v[k]]
            }
        }

        /// `np.gradient`: central differences inside, one-sided at the edges. Returns (d/dy, d/dx).
        static func gradient(_ p: Plane) -> (gy: Plane, gx: Plane) {
            let w = p.width, h = p.height
            var gx = Plane(width: w, height: h), gy = Plane(width: w, height: h)
            p.pixels.withUnsafeBufferPointer { px in
                for y in 0..<h {
                    for x in 0..<w { (gy[x, y], gx[x, y]) = gradient(px, width: w, height: h, x, y) }
                }
            }
            return (gy, gx)
        }

        /// `gradient` at one pixel.
        @inline(__always)
        static func gradient(_ p: UnsafeBufferPointer<Float>, width w: Int, height h: Int, _ x: Int, _ y: Int) -> (gy: Float, gx: Float) {
            let i = y * w + x
            var gx: Float = 0, gy: Float = 0
            if w > 1 { gx = x == 0 ? p[i + 1] - p[i] : x == w - 1 ? p[i] - p[i - 1] : (p[i + 1] - p[i - 1]) / 2 }
            if h > 1 { gy = y == 0 ? p[i + w] - p[i] : y == h - 1 ? p[i] - p[i - w] : (p[i + w] - p[i - w]) / 2 }
            return (gy, gx)
        }
    }

    nonisolated enum Components {
        /// Labels 4- (or 8-) connected components of a mask in raster order of their first pixel
        /// (1, 2, …; 0 is the background) and counts their pixels (`sizes[0]` unused).
        static func label(_ m: [UInt8], width w: Int, height h: Int, eight: Bool = false) -> (labels: [Int32], sizes: [Int]) {
            var labels = [Int32](repeating: 0, count: w * h)
            var sizes = [0]
            var stack = [Int]()
            m.withUnsafeBufferPointer { mm in
                labels.withUnsafeMutableBufferPointer { l in
                    for start in 0..<(w * h) where mm[start] != 0 && l[start] == 0 {
                        let id = Int32(sizes.count)
                        var n = 0
                        l[start] = id; stack.append(start)
                        while let p = stack.popLast() {
                            n += 1
                            let x = p % w, y = p / w
                            @inline(__always) func visit(_ q: Int) {
                                if mm[q] != 0 && l[q] == 0 { l[q] = id; stack.append(q) }
                            }
                            if x > 0 { visit(p - 1) }
                            if x < w - 1 { visit(p + 1) }
                            if y > 0 { visit(p - w) }
                            if y < h - 1 { visit(p + w) }
                            if eight {
                                if x > 0 && y > 0 { visit(p - w - 1) }
                                if x < w - 1 && y > 0 { visit(p - w + 1) }
                                if x > 0 && y < h - 1 { visit(p + w - 1) }
                                if x < w - 1 && y < h - 1 { visit(p + w + 1) }
                            }
                        }
                        sizes.append(n)
                    }
                }
            }
            return (labels, sizes)
        }

        /// `skimage.morphology.remove_small_objects(m, max_size=…)` (4-connected): drops every
        /// component of at most `maxSize` pixels.
        static func removeSmall(_ m: [UInt8], width w: Int, height h: Int, maxSize: Int) -> [UInt8] {
            let (labels, sizes) = label(m, width: w, height: h)
            var out = m
            for i in out.indices where labels[i] > 0 && sizes[Int(labels[i])] <= maxSize { out[i] = 0 }
            return out
        }
    }
}
