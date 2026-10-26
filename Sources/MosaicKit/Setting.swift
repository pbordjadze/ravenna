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

/// v0's saved work, as v1 carries it over (issue #13): region i of a mosaic's template is tile i
/// (`MosaicCore.template(of:)`), and the grout, the last region, is one more.
nonisolated extension Setting {
    /// The template regions this setting has painted, for a mosaic of `tileCount` tiles, ascending:
    /// each set tile's own (indices outside the mosaic dropped), and the grout, which a mosaic's
    /// painting sets first (the canvas's `PaintProgress.groutSet`), so a finished wall is finished.
    public func paintedRegions(tileCount: Int) -> [Int] {
        guard tileCount > 0 else { return [] }
        return set.filter { $0 >= 0 && $0 < tileCount }.sorted() + [tileCount]
    }

    /// What v0 named a setting's file (`Settings/<key>.json`): one of the painter's own mosaics by its
    /// id (`own-…`), or a bundled work at a detail (`<work>-<detail>`); nil for a name that is
    /// neither.
    public static func v0Work(key: String) -> (work: String, detail: Detail?)? {
        if key.hasPrefix("own-") { return (key, nil) }
        for detail in Detail.allCases where key.hasSuffix("-" + detail.rawValue) {
            let work = String(key.dropLast(detail.rawValue.count + 1))
            return work.isEmpty ? nil : (work, detail)
        }
        return nil
    }
}
