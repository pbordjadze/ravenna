/// A painter's work on one mosaic: which tiles are set. Saved as JSON beside the app's other state.
nonisolated public struct Setting: Sendable, Equatable, Codable {
    /// Indices into `Mosaic.tiles`.
    public private(set) var set: Set<Int>

    public init(set: Set<Int> = []) { self.set = set }

    public func isSet(_ tile: Int) -> Bool { set.contains(tile) }

    /// Sets a tile if the painter holds its paint and it isn't set yet; answers whether it did.
    @discardableResult
    public mutating func place(_ tile: Int, with paint: Int, in mosaic: Mosaic) -> Bool {
        guard mosaic.tiles.indices.contains(tile), mosaic.tiles[tile].paint == paint else { return false }
        return set.insert(tile).inserted
    }

    /// Tiles still to set, per paint.
    public func remaining(in mosaic: Mosaic) -> [Int] {
        var n = mosaic.tilesPerPaint
        for i in set where mosaic.tiles.indices.contains(i) { n[mosaic.tiles[i].paint] -= 1 }
        return n
    }

    public func isComplete(_ mosaic: Mosaic) -> Bool { set.count >= mosaic.tiles.count }

    public func fraction(of mosaic: Mosaic) -> Double {
        mosaic.tiles.isEmpty ? 0 : Double(set.count) / Double(mosaic.tiles.count)
    }

    /// The paint to hold next: the first after `paint` (wrapping) with tiles left, or nil when done.
    public func nextPaint(after paint: Int?, in mosaic: Mosaic) -> Int? {
        let left = remaining(in: mosaic)
        let start = (paint ?? -1) + 1
        for k in 0..<left.count {
            let p = (start + k) % left.count
            if left[p] > 0 { return p }
        }
        return nil
    }
}
