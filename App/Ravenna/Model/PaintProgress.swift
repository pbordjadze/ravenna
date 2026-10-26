import Foundation
import PaintCore

/// Persistent painting state of one artwork: which regions are painted, and in what order
/// (the log drives the time-lapse replay).
nonisolated struct PaintProgress: Sendable, Equatable {
    struct Stroke: Sendable, Equatable {
        var region: UInt32
        /// Seconds of active painting time when the region was filled.
        var time: Float
    }

    private(set) var painted: [Bool]
    private(set) var log: [Stroke] = []
    /// Accumulated active painting time.
    var activeSeconds: Double = 0

    init(regionCount: Int) {
        painted = [Bool](repeating: false, count: regionCount)
    }

    var regionCount: Int { painted.count }
    var paintedCount: Int { log.count }
    var isComplete: Bool { !painted.isEmpty && log.count == painted.count }

    func isPainted(_ region: Int) -> Bool { painted[region] }

    /// Marks a region painted; returns false if it already was.
    @discardableResult
    mutating func paint(_ region: Int) -> Bool {
        guard !painted[region] else { return false }
        painted[region] = true
        log.append(Stroke(region: UInt32(region), time: Float(activeSeconds)))
        return true
    }

    /// Reverts the most recent fill.
    mutating func undo() -> Int? {
        guard let last = log.popLast() else { return nil }
        painted[Int(last.region)] = false
        return Int(last.region)
    }

    mutating func reset() {
        painted = [Bool](repeating: false, count: painted.count)
        log.removeAll()
        activeSeconds = 0
    }

    // MARK: Coding (compact binary: header, painting time, stroke log)

    nonisolated enum CodingError: Error, Equatable {
        case corrupt
        /// Written by a newer app; never replace such a file.
        case newerVersion(UInt32)
        /// Progress for more regions than the caller's template has (its count).
        case tooManyRegions(Int)
    }

    private static let magic: UInt32 = 0x5250_4250  // "PBPR"
    /// Fields are only ever appended (readers ignore trailing bytes), so older apps keep
    /// reading newer files; bump only when an existing field changes meaning.
    static let formatVersion: UInt32 = 1

    func encoded() -> Data {
        var data = Data()
        func put<T: BitwiseCopyable>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        put(Self.magic)
        put(Self.formatVersion)
        put(UInt32(painted.count))
        put(activeSeconds)
        put(UInt32(log.count))
        for s in log { put(s.region); put(s.time) }
        return data
    }

    /// `maxRegionCount` is the most regions the caller can use (its template's count): a
    /// larger count throws before the flags are allocated, however large the file claims.
    init(encoded data: Data, maxRegionCount: Int = Template.maxCanvasArea) throws {
        var offset = data.startIndex
        func get<T: BitwiseCopyable>(_: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard size <= data.endIndex - offset else { throw CodingError.corrupt }
            let v = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset - data.startIndex, as: T.self) }
            offset += size
            return v
        }
        guard try get(UInt32.self) == Self.magic else { throw CodingError.corrupt }
        let version = try get(UInt32.self)
        guard version != 0 else { throw CodingError.corrupt }
        guard version <= Self.formatVersion else { throw CodingError.newerVersion(version) }
        // Counts are checked before anything is allocated, so a damaged file cannot ask for gigabytes.
        let count = Int(try get(UInt32.self))
        guard count <= Template.maxCanvasArea else { throw CodingError.corrupt }
        guard count <= maxRegionCount else { throw CodingError.tooManyRegions(count) }
        let seconds = try get(Double.self)
        let strokes = Int(try get(UInt32.self))
        let strokeSize = MemoryLayout<UInt32>.size + MemoryLayout<Float>.size
        guard strokes <= count, strokes <= (data.endIndex - offset) / strokeSize else { throw CodingError.corrupt }
        self.init(regionCount: count)
        activeSeconds = Self.sanitized(seconds)
        log.reserveCapacity(strokes)
        for _ in 0..<strokes {
            let region = try get(UInt32.self)
            let time = try get(Float.self)
            guard Int(region) < count, !painted[Int(region)] else { throw CodingError.corrupt }
            painted[Int(region)] = true
            log.append(Stroke(region: region, time: Float(Self.sanitized(Double(time)))))
        }
    }

    /// A century of active painting is far beyond a real painting, and fits both stroke
    /// times (Float) and the gallery's whole minutes (Int).
    static let maximumActiveSeconds: Double = 100 * 365 * 24 * 60 * 60

    /// Shared with metadata decoding: damaged times must not break replay or the gallery.
    static func sanitized(_ seconds: Double) -> Double {
        seconds.isFinite && seconds > 0 ? min(seconds, maximumActiveSeconds) : 0
    }

    // MARK: Regeneration

    /// This progress carried onto `new`, a regenerated version of `old` (the template it was
    /// painted on): a new region counts as painted when most of its area was painted before
    /// (`RegionRemap`), in the old painting order and with the old stroke times.
    func remapped(from old: Template, to new: Template) -> PaintProgress {
        var result = PaintProgress(regionCount: new.regions.count)
        guard regionCount == old.regions.count else { return result }
        let carried = RegionRemap.carryOver(
            paintOrder: log.map(\.region), oldMap: old.regionMap, oldRegionCount: old.regions.count,
            newMap: new.regionMap, newRegionCount: new.regions.count)
        for c in carried {
            result.painted[c.region] = true
            result.log.append(Stroke(region: UInt32(c.region), time: log[c.stroke].time))
        }
        result.activeSeconds = activeSeconds
        return result
    }
}
