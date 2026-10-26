#if DEBUG
import CoreGraphics
import CryptoKit
import Foundation
import os
import PaintCore

/// Demo and test launches only: the maps and findings `LineArtInputs.maps` computed for a photo,
/// kept on disk in the app's caches by the photo's pixels, so the dozens of launches a CI run
/// makes (one per screenshot scenario and UI test, each seeding the same bundled pictures)
/// run the models and Vision once per picture instead of once per launch. What a launch gets
/// back is exactly what it would compute; a file that doesn't read is recomputed. Keyed by the
/// photo's pixels alone: bump `version` (or delete Caches/LineArtMaps) when a model, `EyeFinder`,
/// `ObjectFinder` or `TextFinder` changes. Release builds have none of this.
nonisolated enum LineArtMapsCache {
    private static let magic = "LAMC"
    /// Also keys `DemoTemplateCache`, whose templates are drawn from these maps.
    static let version: UInt32 = 4

    /// On for demo scenarios (`-demo`, as `DemoMode.scenario` reads it) and the unit-test
    /// host (as `DemoMode.isTestHost` does), never for a painter's own launch; read here
    /// directly, since the maps are computed off the main actor.
    static var isEnabled: Bool {
        UserDefaults.standard.string(forKey: "demo") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appending(path: "LineArtMaps", directoryHint: .isDirectory)
    }

    /// The photo's sRGB pixels hashed: the same picture decoded again gets the same key.
    private static func key(for image: CGImage) -> String? {
        guard let rgba = try? PhotoLoader.rgbaImage(from: image, colorSpace: .sRGB) else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: UInt64(rgba.width).littleEndian) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: UInt64(rgba.height).littleEndian) { hasher.update(bufferPointer: $0) }
        rgba.pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func url(for image: CGImage) -> URL? {
        guard isEnabled, let directory, let key = key(for: image) else { return nil }
        return directory.appending(path: key + ".maps")
    }

    static func maps(for image: CGImage) -> LineArtInputs.Maps? {
        guard let url = url(for: image), let data = try? Data(contentsOf: url) else { return nil }
        guard let maps = decode(data) else {
            Log.create.error("Line art maps cache: \(url.lastPathComponent, privacy: .public) unreadable, recomputing")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return maps
    }

    static func store(_ maps: LineArtInputs.Maps, for image: CGImage) {
        guard let url = url(for: image) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encode(maps).write(to: url, options: .atomic)
        } catch {
            Log.create.error("Line art maps cache: writing failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Coding

    static func encode(_ maps: LineArtInputs.Maps) -> Data {
        var data = Data(magic.utf8)
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ map: EdgeMap) {
            put(UInt32(map.width))
            put(UInt32(map.height))
            data.append(contentsOf: map.values)
        }
        func put(_ polygons: [[SIMD2<Float>]]) {
            put(UInt32(polygons.count))
            for polygon in polygons {
                put(UInt32(polygon.count))
                for p in polygon {
                    put(p.x.bitPattern)
                    put(p.y.bitPattern)
                }
            }
        }
        put(version)
        put(maps.drawing)
        put(maps.contours)
        put(maps.eyes)
        put(maps.objects)
        put(maps.writing)
        return data
    }

    static func decode(_ data: Data) -> LineArtInputs.Maps? {
        var offset = magic.utf8.count
        guard data.count >= offset, String(decoding: data.prefix(offset), as: UTF8.self) == magic else { return nil }
        func take<T: FixedWidthInteger>(_: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard data.count - offset >= size else { return nil }
            var value = T()
            withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: data[(data.startIndex + offset)..<(data.startIndex + offset + size)]) }
            offset += size
            return T(littleEndian: value)
        }
        func takeMap() -> EdgeMap? {
            guard let w = take(UInt32.self), let h = take(UInt32.self), w > 0, h > 0, w <= 8192, h <= 8192 else { return nil }
            let count = Int(w) * Int(h)
            guard data.count - offset >= count else { return nil }
            let values = [UInt8](data[(data.startIndex + offset)..<(data.startIndex + offset + count)])
            offset += count
            return EdgeMap(width: Int(w), height: Int(h), values: values)
        }
        func takePolygons() -> [[SIMD2<Float>]]? {
            guard let count = take(UInt32.self), count <= 4096 else { return nil }
            var polygons: [[SIMD2<Float>]] = []
            for _ in 0..<count {
                guard let points = take(UInt32.self), points <= 1_000_000, data.count - offset >= Int(points) * 8 else { return nil }
                var polygon: [SIMD2<Float>] = []
                polygon.reserveCapacity(Int(points))
                for _ in 0..<points {
                    guard let x = take(UInt32.self), let y = take(UInt32.self) else { return nil }
                    polygon.append(SIMD2(Float(bitPattern: x), Float(bitPattern: y)))
                }
                polygons.append(polygon)
            }
            return polygons
        }
        guard take(UInt32.self) == version, let drawing = takeMap(), let contours = takeMap(),
              let eyes = takePolygons(), let objects = takePolygons(), let writing = takePolygons(), offset == data.count
        else { return nil }
        return LineArtInputs.Maps(drawing: drawing, contours: contours, eyes: eyes, objects: objects, writing: writing)
    }
}
#endif
