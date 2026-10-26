import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import os
import PaintCore

/// Mosaics started in v0 (Ravenna's first app, `App/v0/`, the same bundle identifier and so the
/// same container), carried into the library once, with their progress (issue #13). v0 kept them
/// in Application Support (`App/v0/Library.swift`):
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
/// the next.
///
/// Ravenna's seam: Paint by Moonlight has no v0.
nonisolated enum V0CarryOver {
    /// Set once nothing is left to carry.
    static let doneKey = "v0.carriedOver"
    /// The v0 keys (`Setting.v0Work(key:)`'s) already carried.
    static let carriedKey = "v0.carriedWorks"

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

    /// Whether v0 left anything behind.
    static var hasWorks: Bool {
        let fm = FileManager.default
        return [settingsDirectory, ownDirectory].contains { (try? fm.contentsOfDirectory(atPath: $0.path(percentEncoded: false)))?.isEmpty == false }
    }

    /// v0's works not yet carried, as v0's own files and options have them. A file that doesn't
    /// read is logged and passed over.
    static func works(skipping carried: Set<String>, ground: MosaicEngine.Ground) -> [Work] {
        let fm = FileManager.default
        var found: [Work] = []
        // The painter's own, setting or none.
        let own = (try? fm.contentsOfDirectory(at: ownDirectory, includingPropertiesForKeys: nil)) ?? []
        for dir in own where !carried.contains(dir.lastPathComponent) {
            do {
                let work = try JSONDecoder().decode(OwnWork.self, from: Data(contentsOf: dir.appending(path: "work.json")))
                let mosaic = try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: dir.appending(path: "mosaic.json")))
                let photo = dir.appending(path: "photo.jpg")
                found.append(Work(
                    key: dir.lastPathComponent, title: work.title, date: work.made ?? .now, mosaic: mosaic,
                    recipe: MosaicEngine.Recipe(ground: ground), sampleName: nil,
                    photo: fm.fileExists(atPath: photo.path(percentEncoded: false)) ? photo : nil,
                    setting: setting(dir.lastPathComponent) ?? Setting()))
            } catch {
                Log.library.error("v0's mosaic \(dir.lastPathComponent, privacy: .public) can't be read: \(String(describing: error), privacy: .public)")
            }
        }
        // The bundled works the painter set tiles of, at each detail.
        let files = (try? fm.contentsOfDirectory(at: settingsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            guard !carried.contains(key), case let (id, detail?)? = Setting.v0Work(key: key),
                  let saved = setting(key), !saved.set.isEmpty, let sample = Sample.named(id),
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
        return found
    }

    /// v0's record of one of the painter's own mosaics (`work.json`), as much of it as is carried.
    private struct OwnWork: Decodable {
        var id: String
        var title: String
        var made: Date?
    }

    private static func setting(_ key: String) -> Setting? {
        let url = settingsDirectory.appending(path: "\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Setting.self, from: data)
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
    /// Carries v0's mosaics into the library at launch, once (`V0CarryOver`), off the main actor;
    /// a painter coming from v0 has their gallery already, so the first launch's starters aren't
    /// made for them.
    func carryOverV0IfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: V0CarryOver.doneKey) else { return }
        guard V0CarryOver.hasWorks else {
            defaults.set(true, forKey: V0CarryOver.doneKey)
            return
        }
        defaults.set(true, forKey: Self.seededKey)
        let carried = Set(defaults.stringArray(forKey: V0CarryOver.carriedKey) ?? [])
        // v0's gold ground, an option for every mosaic, becomes each carried work's own.
        let ground = MosaicEngine.Ground(rawValue: defaults.string(forKey: "ground") ?? "") ?? .picture
        Task(priority: .utility) {
            let works = await Background.run { V0CarryOver.works(skipping: carried, ground: ground) }
            var done = carried, failed = false
            for work in works {
                // Made by a launch that ended before it could note it: carried already.
                if artworks.contains(where: { $0.title == work.title && $0.createdAt == work.date && $0.sampleName == work.sampleName }) {
                    done.insert(work.key)
                    defaults.set(Array(done).sorted(), forKey: V0CarryOver.carriedKey)
                    continue
                }
                do {
                    let draft = try await Background.run { try V0CarryOver.draft(of: work) }
                    try await create(draft)
                    done.insert(work.key)
                    defaults.set(Array(done).sorted(), forKey: V0CarryOver.carriedKey)
                    Log.library.notice("Carried v0's \(work.key, privacy: .public) over")
                } catch {
                    failed = true
                    Log.library.error("Carrying v0's \(work.key, privacy: .public) over failed: \(String(describing: error), privacy: .public)")
                }
            }
            if !failed { defaults.set(true, forKey: V0CarryOver.doneKey) }
        }
    }
}
