import Foundation
import Observation
import SwiftUI
import UIKit

/// A work to set: an ancient picture in the public domain that came with the app (laid as a mosaic
/// at each detail by `sketchbook/bundle.py`), or the painter's own photo, laid on the device.
struct Work: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var date: String
    var place: String
    var medium: String
    var credit: String
    /// The work's page (the Met's, for the bundled ones).
    var url: URL?
    /// Tiles at each detail, by `Detail.rawValue`; the painter's own have one count, under "own".
    var tiles: [String: Int]
    /// The painter's own: one mosaic, in its folder on the device, and when it was made.
    var own: Bool? = nil
    var made: Date? = nil

    var isOwn: Bool { own ?? false }
}

/// The collection, the painter's options and their work on each mosaic.
@Observable
final class Library {
    let works: [Work]
    /// The painter's own mosaics, newest first.
    private(set) var own: [Work] = []
    /// The options until Paul narrows them (issues #6, #11, #12).
    var finish: Finish { didSet { defaults.set(finish.rawValue, forKey: "finish") } }
    var detail: Detail { didSet { defaults.set(detail.rawValue, forKey: "detail") } }

    /// Read and written as the painter works; `revision` is what views watch.
    @ObservationIgnored private var settings: [String: Setting] = [:]
    private(set) var revision = 0
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var images: [String: UIImage] = [:]

    init() {
        struct Catalog: Decodable { var mosaics: [Work] }
        let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
        works = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) }?.mosaics ?? []
        finish = Finish(rawValue: UserDefaults.standard.string(forKey: "finish") ?? "") ?? .material
        detail = Detail(rawValue: UserDefaults.standard.string(forKey: "detail") ?? "") ?? .standard
        own = loadOwn()
    }

    /// The mosaic of a work (at a detail, for the bundled ones), read off the main thread.
    func mosaic(_ work: Work, _ detail: Detail) async throws -> Mosaic {
        let url: URL
        if work.isOwn {
            url = folder(work).appending(path: "mosaic.json")
        } else {
            guard let u = Bundle.main.url(forResource: "\(work.id)-\(detail.rawValue)", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            url = u
        }
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: url))
        }.value
    }

    /// A work's painted bed ("bed") or its picture ("photo").
    func image(_ work: Work, _ kind: String) -> UIImage? {
        let key = "\(work.id)-\(kind)"
        if let i = images[key] { return i }
        let i = work.isOwn
            ? UIImage(contentsOfFile: folder(work).appending(path: "\(kind).jpg").path(percentEncoded: false))
            : Bundle.main.path(forResource: key, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
        images[key] = i
        return i
    }

    /// Keeps a mosaic made from the painter's photo, in its own folder on the device.
    func keep(_ made: Maker.Made) throws -> Work {
        let id = "own-\(UUID().uuidString.lowercased())"
        let now = Date.now
        var work = Work(id: id, title: "Your mosaic", date: now.formatted(date: .abbreviated, time: .shortened),
                        place: "From your photo", medium: "", credit: "Your photo stays on this device.", url: nil,
                        tiles: ["own": made.mosaic.tiles.count], own: true, made: now)
        let dir = folder(work)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(made.mosaic).write(to: dir.appending(path: "mosaic.json"))
        try made.photo.write(to: dir.appending(path: "photo.jpg"))
        try made.bed.write(to: dir.appending(path: "bed.jpg"))
        work.title = "Your mosaic, \(now.formatted(date: .abbreviated, time: .omitted))"
        try JSONEncoder().encode(work).write(to: dir.appending(path: "work.json"))
        own.insert(work, at: 0)
        return work
    }

    /// Removes one of the painter's own mosaics, with their work on it.
    func remove(_ work: Work) {
        guard work.isOwn else { return }
        try? FileManager.default.removeItem(at: folder(work))
        try? FileManager.default.removeItem(at: file(settingKey(work, detail)))
        settings[settingKey(work, detail)] = nil
        own.removeAll { $0.id == work.id }
    }

    // MARK: The painter's work, one file per work (and detail, for the bundled ones)

    func setting(_ work: Work, _ detail: Detail) -> Setting {
        let key = settingKey(work, detail)
        if let s = settings[key] { return s }
        let s = (try? Data(contentsOf: file(key))).flatMap { try? JSONDecoder().decode(Setting.self, from: $0) } ?? Setting()
        settings[key] = s
        return s
    }

    func save(_ setting: Setting, _ work: Work, _ detail: Detail) {
        let key = settingKey(work, detail)
        settings[key] = setting
        revision += 1
        try? JSONEncoder().encode(setting).write(to: file(key), options: .atomic)
    }

    /// How far the painter is with a work at the current detail, 0...1, without reading its mosaic.
    func progress(_ work: Work) -> Double {
        _ = revision
        guard let tiles = work.tiles[work.isOwn ? "own" : detail.rawValue], tiles > 0 else { return 0 }
        return Double(setting(work, detail).set.count) / Double(tiles)
    }

    private func settingKey(_ work: Work, _ detail: Detail) -> String {
        work.isOwn ? work.id : "\(work.id)-\(detail.rawValue)"
    }

    private func file(_ key: String) -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Settings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(key).json")
    }

    private static var ownRoot: URL { URL.applicationSupportDirectory.appending(path: "Own", directoryHint: .isDirectory) }

    private func folder(_ work: Work) -> URL { Self.ownRoot.appending(path: work.id, directoryHint: .isDirectory) }

    private func loadOwn() -> [Work] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Self.ownRoot, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { try? JSONDecoder().decode(Work.self, from: Data(contentsOf: $0.appending(path: "work.json"))) }
            .sorted { ($0.made ?? .distantPast) > ($1.made ?? .distantPast) }
    }
}
