import Foundation
import Observation
import SwiftUI
import UIKit

/// A work in the bundled collection: an ancient picture in the public domain, laid as a mosaic at
/// each detail (`sketchbook/bundle.py` makes them).
struct Work: Identifiable, Hashable, Decodable {
    var id: String
    var title: String
    var date: String
    var place: String
    var medium: String
    var credit: String
    var url: URL
    /// Tiles at each detail, by `Detail.rawValue`.
    var tiles: [String: Int]
}

/// The collection, the painter's options and their work on each mosaic.
@Observable
final class Library {
    let works: [Work]
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
    }

    /// The mosaic of a work at a detail, read off the main thread.
    func mosaic(_ work: Work, _ detail: Detail) async throws -> Mosaic {
        guard let url = Bundle.main.url(forResource: "\(work.id)-\(detail.rawValue)", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode(Mosaic.self, from: Data(contentsOf: url))
        }.value
    }

    /// The painted bed under a work's tiles, or its picture.
    func image(_ work: Work, _ kind: String) -> UIImage? {
        let key = "\(work.id)-\(kind)"
        if let i = images[key] { return i }
        let i = Bundle.main.path(forResource: key, ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
        images[key] = i
        return i
    }

    // MARK: The painter's work, one file per work and detail

    func setting(_ work: Work, _ detail: Detail) -> Setting {
        let key = "\(work.id)-\(detail.rawValue)"
        if let s = settings[key] { return s }
        let s = (try? Data(contentsOf: file(key))).flatMap { try? JSONDecoder().decode(Setting.self, from: $0) } ?? Setting()
        settings[key] = s
        return s
    }

    func save(_ setting: Setting, _ work: Work, _ detail: Detail) {
        let key = "\(work.id)-\(detail.rawValue)"
        settings[key] = setting
        revision += 1
        try? JSONEncoder().encode(setting).write(to: file(key), options: .atomic)
    }

    /// How far the painter is with a work at the current detail, 0...1, without reading its mosaic.
    func progress(_ work: Work) -> Double {
        _ = revision
        guard let tiles = work.tiles[detail.rawValue], tiles > 0 else { return 0 }
        return Double(setting(work, detail).set.count) / Double(tiles)
    }

    private func file(_ key: String) -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Settings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(key).json")
    }
}
