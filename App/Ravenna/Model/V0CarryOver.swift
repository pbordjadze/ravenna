import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import os
import PaintCore

/// Mosaics started in v0 (Ravenna's first app, the same bundle identifier and so the same
/// container; its code is `App/v0/` in the history, up to 108a3c7), carried into the library once,
/// with their progress (issue #13). v0 kept them in Application Support (its `Library.swift`):
///
///     Own/<own-id>/work.json, mosaic.json, photo.jpg   a mosaic of the painter's own photo
///     Settings/<own-id>.json                          its tiles set (`Setting`)
///     Settings/<work>-<detail>.json                   a bundled work's tiles set at a detail
///
/// and the finish and the gold ground as options for every mosaic (UserDefaults `finish`,
/// `ground`). v1 keeps the finish as it is (`MosaicLook`) and records the ground with each work,
/// so it opens as it looked. Each becomes an artwork: its mosaic (a bundled work's from the
/// bundle) with that ground laid on, which moves no tile, its template made of it, and its set
/// tiles painted (`Setting.paintedRegions`: region i is tile i, the grout set). Only works with tiles set come over from the
/// bundled ones; every one of the painter's own does. v0's files are left where they are, and
/// each work is carried once (`carriedKey`), so a launch that ends half way carries the rest at
/// the next. A file that can't be read just now (the device locked, an I/O error) leaves the
/// carry-over to a later launch, its work uncarried; a damaged one is passed over; a work that
/// fails to become an artwork `maxAttempts` launches running is given up. An own work's Pieces
/// are the nearest v0's (`pieces(of:)`), so a regenerated mosaic is as dense.
///
/// Ravenna's seam: Paint by Moonlight has no v0.
nonisolated enum V0CarryOver {
    /// Set once nothing is left to carry.
    static let doneKey = "v0.carriedOver"
    /// The v0 keys (`Setting.v0Work(key:)`'s) already carried.
    static let carriedKey = "v0.carriedWorks"
    /// Launches that tried to carry each v0 key and failed: a work that never makes an artwork
    /// (an old mosaic the template can't be made of) is given up after `maxAttempts`, rather
    /// than tried at every launch.
    static let attemptsKey = "v0.carryAttempts"
    static let maxAttempts = 3

    /// One of v0's works, ready to be an artwork.
    struct Work: Sendable {
        var key: String
        var title: String
        var date: Date
        var mosaic: Mosaic
        var recipe: MosaicEngine.Recipe
        var sampleName: String?
        var photo: URL?
        var setting: Setting
    }

    private static var root: URL { URL.applicationSupportDirectory }
    private static var settingsDirectory: URL { root.appending(path: "Settings", directoryHint: .isDirectory) }
    private static var ownDirectory: URL { root.appending(path: "Own", directoryHint: .isDirectory) }

    /// Whether v0 left anything behind, or may have: a folder that can't be listed just now
    /// counts, so the carry-over runs and tries again later.
    static var hasWorks: Bool {
        [settingsDirectory, ownDirectory].contains { contents(of: $0).map { !$0.isEmpty } ?? true }
    }

    /// What reading one of v0's files came to: damage (missing or corrupt, `Library.isDamage`)
    /// is told apart from a read that fails just now (the device locked, an I/O error), which
    /// a later launch tries again.
    enum FileRead<Value> {
        case read(Value)
        case absent
        case damaged
        case unreadable
    }

    private static func read<Value: Decodable>(_ type: Value.Type, at url: URL) -> FileRead<Value> {
        let data: Data
        switch bytes(at: url) {
        case .read(let read): data = read
        case .absent: return .absent
        case .damaged: return .damaged
        case .unreadable: return .unreadable
        }
        do {
            return .read(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            Log.library.error("v0's \(url.lastPathComponent, privacy: .public) doesn't decode: \(String(describing: error), privacy: .public)")
            return .damaged
        }
    }

    private static func bytes(at url: URL) -> FileRead<Data> {
        do {
            return .read(try Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .absent
        } catch let error as CocoaError where Library.isDamage(error) {
            Log.library.error("v0's \(url.lastPathComponent, privacy: .public) is damaged: \(String(describing: error), privacy: .public)")
            return .damaged
        } catch {
            Log.library.error("v0's \(url.lastPathComponent, privacy: .public) can't be read now: \(String(describing: error), privacy: .public)")
            return .unreadable
        }
    }

    /// A folder's files: none when it isn't there, nil when it can't be listed just now.
    private static func contents(of directory: URL) -> [URL]? {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where Library.isDamage(error) {
            return []
        } catch {
            Log.library.error("v0's \(directory.lastPathComponent, privacy: .public) can't be listed now: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// v0's works not yet carried, as v0's own files and options have them, and whether any
    /// couldn't be read just now (`failed`: the carry-over isn't done). A damaged file is logged
    /// and passed over; a damaged setting of the painter's own mosaic carries it unset.
    static func works(skipping carried: Set<String>, ground: MosaicEngine.Ground) -> (works: [Work], failed: Bool) {
        var found: [Work] = [], failed = false
        // The painter's own, setting or none.
        let own = contents(of: ownDirectory)
        if own == nil { failed = true }
        for dir in own ?? [] where !carried.contains(dir.lastPathComponent) {
            let key = dir.lastPathComponent
            switch (read(OwnWork.self, at: dir.appending(path: "work.json")), read(Mosaic.self, at: dir.appending(path: "mosaic.json"))) {
            case let (.read(work), .read(mosaic)):
                let setting: Setting
                switch read(Setting.self, at: settingURL(key)) {
                case .read(let saved): setting = saved
                case .absent, .damaged: setting = Setting()
                case .unreadable:
                    failed = true
                    continue
                }
                // The photo too: one carried without it can never be laid again.
                let photo = dir.appending(path: "photo.jpg")
                let hasPhoto: Bool
                switch bytes(at: photo) {
                case .read(let data): hasPhoto = !data.isEmpty
                case .absent, .damaged: hasPhoto = false
                case .unreadable:
                    failed = true
                    continue
                }
                found.append(Work(
                    key: key, title: work.title, date: work.made ?? made(dir) ?? .now, mosaic: mosaic,
                    recipe: MosaicEngine.Recipe(pieces: pieces(of: mosaic), ground: ground), sampleName: nil,
                    photo: hasPhoto ? photo : nil,
                    setting: setting))
            case (.unreadable, _), (_, .unreadable):
                failed = true
            default:
                Log.library.error("v0's mosaic \(key, privacy: .public) can't be carried: its files are missing or damaged")
            }
        }
        // The bundled works the painter set tiles of, at each detail.
        let files = contents(of: settingsDirectory)
        if files == nil { failed = true }
        for file in files ?? [] where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            guard !carried.contains(key), case let (id, detail?)? = Setting.v0Work(key: key) else { continue }
            let saved: Setting
            switch read(Setting.self, at: file) {
            case .read(let setting): saved = setting
            case .unreadable:
                failed = true
                continue
            case .absent, .damaged: continue
            }
            guard !saved.set.isEmpty, let sample = Sample.named(id),
                  let pieces = MosaicEngine.Recipe.detailPieces[detail] else { continue }
            let recipe = MosaicEngine.Recipe(pieces: pieces, ground: ground)
            // Its tiles, before the ground: `draft` lays it on.
            guard let mosaic = MosaicMaker.bundled(id, recipe: MosaicEngine.Recipe(pieces: pieces)) else {
                Log.library.error("v0's work \(key, privacy: .public) has no bundled mosaic")
                continue
            }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            found.append(Work(key: key, title: sample.title, date: date, mosaic: mosaic, recipe: recipe, sampleName: id,
                              photo: sample.url, setting: saved))
        }
        return (found, failed)
    }

    /// v0's record of one of the painter's own mosaics (`work.json`), as much of it as is carried.
    private struct OwnWork: Decodable {
        var id: String
        var title: String
        var made: Date?
    }

    /// When v0 made a folder: a work's date where its record has none, the same at every launch,
    /// so one carried by a launch that ended before noting it is known.
    private static func made(_ dir: URL) -> Date? {
        (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    private static func settingURL(_ key: String) -> URL { settingsDirectory.appending(path: "\(key).json") }

    /// The Pieces nearest the ones v0 laid `mosaic` at: v0's photo was cut to the recipe's long
    /// side (`Recipe.longSide`, the same sum), so a regenerated mosaic is as dense. A photo
    /// smaller than that side reads as fewer.
    static func pieces(of mosaic: Mosaic) -> Double {
        let side = Double(max(mosaic.width, mosaic.height))
        guard side > 0 else { return MosaicEngine.Recipe.standardPieces }
        return min(max(log(2 * pow(side / 1024, 2)) / log(6), 0), 1)
    }

    /// The artwork a v0 work becomes: its mosaic with its ground laid on, its template, and its set
    /// tiles painted.
    static func draft(of work: Work) throws -> ArtworkDraft {
        let mosaic = work.recipe.laid(work.mosaic)
        let template = try MosaicMaker.template(of: mosaic)
        if let last = work.setting.set.max(), last >= mosaic.tiles.count {
            Log.library.error("v0's \(work.key, privacy: .public) sets tile \(last) of \(mosaic.tiles.count): an older mosaic's")
        }
        var progress = PaintProgress(regionCount: template.regions.count)
        for region in work.setting.paintedRegions(tileCount: mosaic.tiles.count) where region < template.regions.count {
            progress.paint(region)
        }
        let photo = work.photo.flatMap { ImageCodec.image(at: $0, maxPixelSize: ArtworkStore.sourceMaxPixelSize) }
        return ArtworkDraft(
            title: work.title, template: template, settings: GenerationSettings(), photo: photo, sampleName: work.sampleName,
            progress: progress, date: work.date, mosaic: mosaic, recipe: work.recipe)
    }
}

extension Library {
    /// Carries v0's mosaics into the library at launch, once (`V0CarryOver`), off the main actor,
    /// and answers whether it has begun. The first launch's starters wait for it: they are made
    /// only if it ends with the library still empty (`seedIfNeeded`), so a painter coming from v0
    /// has their gallery, and one whose v0 works all failed to come over still has starters.
    @discardableResult
    func carryOverV0IfNeeded(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: V0CarryOver.doneKey) else { return false }
        guard V0CarryOver.hasWorks else {
            defaults.set(true, forKey: V0CarryOver.doneKey)
            return false
        }
        let carried = Set(defaults.stringArray(forKey: V0CarryOver.carriedKey) ?? [])
        // v0's gold ground, an option for every mosaic, becomes each carried work's own.
        let ground = MosaicEngine.Ground(rawValue: defaults.string(forKey: "ground") ?? "") ?? .picture
        Task(priority: .utility) {
            let (works, unread) = await Background.run { V0CarryOver.works(skipping: carried, ground: ground) }
            var done = carried, failed = unread
            var attempts = defaults.dictionary(forKey: V0CarryOver.attemptsKey) as? [String: Int] ?? [:]
            for work in works {
                // Made by a launch that ended before it could note it: carried already.
                if artworks.contains(where: { $0.title == work.title && $0.createdAt == work.date && $0.sampleName == work.sampleName }) {
                    done.insert(work.key)
                    defaults.set(Array(done).sorted(), forKey: V0CarryOver.carriedKey)
                    continue
                }
                // Counted before it is tried, as seeding counts: a launch that ends while carrying
                // it counts too.
                let attempt = attempts[work.key, default: 0] + 1
                attempts[work.key] = attempt
                defaults.set(attempts, forKey: V0CarryOver.attemptsKey)
                do {
                    let draft = try await Background.run { try V0CarryOver.draft(of: work) }
                    try await create(draft)
                    done.insert(work.key)
                    defaults.set(Array(done).sorted(), forKey: V0CarryOver.carriedKey)
                    Log.library.notice("Carried v0's \(work.key, privacy: .public) over")
                } catch let error where attempt >= V0CarryOver.maxAttempts {
                    // v0's files stay where they are; only the trying stops.
                    done.insert(work.key)
                    defaults.set(Array(done).sorted(), forKey: V0CarryOver.carriedKey)
                    Log.library.fault("Gave up carrying v0's \(work.key, privacy: .public) over after \(attempt) launches: \(String(describing: error), privacy: .public)")
                } catch {
                    failed = true
                    Log.library.error("Carrying v0's \(work.key, privacy: .public) over failed: \(String(describing: error), privacy: .public)")
                }
            }
            if !failed {
                defaults.set(true, forKey: V0CarryOver.doneKey)
                defaults.removeObject(forKey: V0CarryOver.attemptsKey)
            }
            seedIfNeeded(defaults: defaults)
        }
        return true
    }
}
