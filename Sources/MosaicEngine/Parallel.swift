import Dispatch

nonisolated extension MosaicEngine {
    /// Work spread over the cores. Each part computes exactly what it would alone (the same
    /// arithmetic in the same order for each pixel or row it owns), so the mosaic is the same bits
    /// however many cores there are and however the parts interleave. The parts are cut by the
    /// work's size alone, never by the core count, and no part keeps a partial sum of its own: a
    /// total is summed in order afterwards (KMeans.assign).
    nonisolated enum Parallel {
        /// Calls `body` with consecutive ranges covering `0..<n`, several at once. A range owns its
        /// indices: `body` writes only to what they index, through pointers taken before the call
        /// (an array written from several threads at once would trip Swift's exclusivity checks).
        /// `grain` is the least worth a part of its own.
        static func ranges(_ n: Int, grain: Int = 1, _ body: (Range<Int>) -> Void) {
            guard n > 0 else { return }
            let parts = Swift.min(Swift.max(n / Swift.max(grain, 1), 1), 64)
            if parts == 1 { body(0..<n); return }
            withoutActuallyEscaping(body) { body in
                let work = Unchecked(body)
                DispatchQueue.concurrentPerform(iterations: parts) { p in
                    work.value((p * n / parts)..<((p + 1) * n / parts))
                }
            }
        }

        /// `(0..<n).map(f)`, its parts made at once.
        static func map<T>(_ n: Int, grain: Int = 1, zero: T, _ f: (Int) -> T) -> [T] {
            var out = [T](repeating: zero, count: n)
            out.withUnsafeMutableBufferPointer { o in
                let o = Unchecked(o)
                ranges(n, grain: grain) { r in for i in r { o.value[i] = f(i) } }
            }
            return out
        }

        /// Hands what isn't `Sendable` (a closure, a buffer pointer) to the parts, which use it as
        /// `ranges` says.
        nonisolated struct Unchecked<T>: @unchecked Sendable {
            let value: T
            init(_ value: T) { self.value = value }
        }
    }
}
