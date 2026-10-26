import CoreGraphics
import Foundation
import UIKit

/// Decoded images kept for reuse, bounded by their decoded size and dropped least recently
/// used first. Everything goes when the system warns about memory: decoding again is cheap,
/// being terminated is not.
final class ImageCache<Key: Hashable> {
    private var entries: [Key: (image: CGImage, cost: Int, lastUse: Int)] = [:]
    private var useClock = 0
    private(set) var totalCost = 0
    /// Decoded bytes the cache may hold.
    let costLimit: Int
    private var memoryWarnings: NotificationObservation?

    init(costLimit: Int) {
        self.costLimit = costLimit
        memoryWarnings = NotificationObservation(UIApplication.didReceiveMemoryWarningNotification) { [weak self] in
            self?.removeAll()
        }
    }

    func image(for key: Key) -> CGImage? {
        guard let entry = entries[key] else { return nil }
        useClock += 1
        entries[key]?.lastUse = useClock
        return entry.image
    }

    /// The most recently used image whose key matches.
    func mostRecent(where matches: (Key) -> Bool) -> CGImage? {
        guard let match = entries.filter({ matches($0.key) }).max(by: { $0.value.lastUse < $1.value.lastUse })
        else { return nil }
        useClock += 1
        entries[match.key]?.lastUse = useClock
        return match.value.image
    }

    /// Keeps `image`, evicting the least recently used ones to stay within the limit. An image
    /// larger than the whole budget isn't kept (the caller still has it).
    func insert(_ image: CGImage, for key: Key) {
        let cost = Self.cost(of: image)
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost <= costLimit else { return }
        // A linear scan per eviction: the cache holds at most about a hundred images, so a
        // linked list would buy nothing.
        while totalCost + cost > costLimit,
              let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })
        {
            totalCost -= oldest.value.cost
            entries[oldest.key] = nil
        }
        useClock += 1
        entries[key] = (image, cost, useClock)
        totalCost += cost
    }

    func removeAll() {
        entries.removeAll()
        totalCost = 0
    }

    /// Bytes of the decoded bitmap.
    nonisolated static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}

/// Calls `handler` on the main actor for each `name` notification until it is released.
nonisolated private final class NotificationObservation {
    private let token: any NSObjectProtocol

    /// The block runs on the main queue but must not be MainActor-isolated itself (Swift 6
    /// checks that at runtime), so it is formed here, outside the main actor.
    init(_ name: Notification.Name, handler: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Decoded gallery thumbnails, keyed by artwork, thumbnail version and the pixel size a tile
/// shows them at (a full-size thumbnail is 4 MB decoded; a phone tile needs a quarter of that).
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// Together with `SampleImages.costLimit`, about 64 MB of decoded images.
    static let costLimit = 48 << 20

    private struct Key: Hashable {
        let id: UUID
        let version: Int
        let pixelSize: Int
    }

    private let images = ImageCache<Key>(costLimit: ThumbnailCache.costLimit)

    /// Identifies the thumbnail's content: changes whenever the artwork's thumbnail is redrawn.
    static func key(_ artwork: Artwork) -> String { "\(artwork.id.uuidString)#\(artwork.thumbnailVersion)" }

    func cached(_ artwork: Artwork, maxPixelSize: Int) -> CGImage? {
        images.image(for: Key(id: artwork.id, version: artwork.thumbnailVersion, pixelSize: maxPixelSize))
    }

    /// The current thumbnail at whatever size was decoded last: a stand-in while the right
    /// size loads, so tiles and the zoom transition never flash empty.
    func bestCached(_ artwork: Artwork) -> CGImage? {
        images.mostRecent { $0.id == artwork.id && $0.version == artwork.thumbnailVersion }
    }

    func load(_ artwork: Artwork, maxPixelSize: Int, from store: ArtworkStore) async -> CGImage? {
        let key = Key(id: artwork.id, version: artwork.thumbnailVersion, pixelSize: maxPixelSize)
        if let hit = images.image(for: key) { return hit }
        let id = artwork.id
        // A tile scrolled away before its turn came decodes nothing.
        guard let image = await Background.run({ Task.isCancelled ? nil : store.thumbnail(id, maxPixelSize: maxPixelSize) })
        else { return nil }
        images.insert(image, for: key)
        return image
    }

    /// The long side, in pixels, of a thumbnail shown in `frame`, rounded up to a multiple of
    /// 128 so small layout changes don't decode it again. 0 before the frame is laid out.
    nonisolated static func pixelSize(frame: CGSize, displayScale: CGFloat, aspectRatio: CGFloat, fills: Bool) -> Int {
        guard frame.width > 0, frame.height > 0, aspectRatio > 0 else { return 0 }
        // The image as (aspectRatio, 1), scaled to fill or fit the frame.
        let widthScale = frame.width / aspectRatio
        let height = fills ? max(widthScale, frame.height) : min(widthScale, frame.height)
        let longSide = height * max(aspectRatio, 1) * max(displayScale, 1)
        let bucket = Int((longSide / 128).rounded(.up)) * 128
        return min(max(bucket, 128), ArtworkStore.thumbnailMaxPixelSize)
    }
}

/// Downscaled bundled sample pictures for tiles and placeholders.
final class SampleImages {
    static let shared = SampleImages()
    /// About a dozen 640 px tiles, more than the Samples pane shows at once: the library holds
    /// dozens of pictures, so tiles scrolled far away decode again instead of staying in memory.
    static let costLimit = 16 << 20

    private let images = ImageCache<String>(costLimit: SampleImages.costLimit)

    func load(_ sample: Sample, maxPixelSize: Int) async -> CGImage? {
        let key = "\(sample.id)@\(maxPixelSize)"
        if let hit = images.image(for: key) { return hit }
        guard let url = sample.url else { return nil }
        guard let image = await Background.run({ ImageCodec.image(at: url, maxPixelSize: maxPixelSize) }) else { return nil }
        images.insert(image, for: key)
        return image
    }
}
