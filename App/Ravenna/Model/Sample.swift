import Foundation
import os

/// A picture bundled with the app (`Resources/Samples/<id>.jpg`).
///
/// `Resources/Samples/library.json` is the library: the pictures the Samples pane offers, in
/// their curated order, and where each one comes from (a record per picture, with its license
/// evidence). Creator, year, credit and license are proper names and facts, read from there
/// and shown verbatim in every language. Titles are translated: each is the string catalog's
/// `sample.<id>`, looked up at runtime with the record's title as its English.
/// `tools/strings_check.py` keeps the catalog and the file in step, `SampleLibraryTests` the
/// file, the titles and the bundled JPEGs.
nonisolated struct Sample: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Decodable, Sendable {
        case painting, photograph
    }

    /// Who made a picture and the terms it ships under, as its `library.json` record has them.
    struct Provenance: Hashable, Decodable, Sendable {
        let kind: Kind
        let creator: String
        /// As the source dates the work: "1968", "c. 1830–32".
        let year: String
        /// The collection or agency the file comes from.
        let credit: String
        let license: String
    }

    let id: String
    let title: String
    let provenance: Provenance?

    init(id: String, title: String, provenance: Provenance? = nil) {
        self.id = id
        self.title = title
        self.provenance = provenance
    }

    var url: URL? { Bundle.main.url(forResource: id, withExtension: "jpg") }

    /// The pictures the Samples pane offers, in the order of `library.json` (which is
    /// authoritative: curating the library reorders the file, not this code).
    static let all: [Sample] = {
        guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            Log.library.fault("library.json is missing from the bundle")
            return []
        }
        return Sample.listed(in: data)
    }()

    /// The pictures of one kind, in the library's order: a section of the Samples pane.
    static func all(of kind: Kind) -> [Sample] { all.filter { $0.provenance?.kind == kind } }

    /// Prepared on first launch so the gallery starts with something to paint: a painting and
    /// a photograph, the library's best first impression.
    static let starters: [Sample] = ["great-wave", "delicate-arch"].compactMap(Sample.named)

    /// The library picture `id` names. Saved paintings name theirs (`Artwork.sampleName`) and
    /// regenerate from it when they have no stored photo; one the library no longer offers
    /// resolves to nil, so such a painting can't be regenerated (`ArtworkFactory.canRegenerate`).
    static func named(_ id: String) -> Sample? {
        all.first { $0.id == id }
    }

    /// The pictures a `library.json` lists, in its order, each titled by the catalog's
    /// `sample.<id>` (the record's own title where the catalog has none). A file that doesn't
    /// decode, a record missing its title or one of its facts included, lists nothing (and
    /// `SampleLibraryTests` fails).
    static func listed(in data: Data) -> [Sample] {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            Log.library.fault("library.json doesn't decode: \(String(describing: error), privacy: .public)")
            return []
        }
        return records.map { record in
            let title = Bundle.main.localizedString(forKey: "sample.\(record.id)", value: record.title, table: nil)
            return Sample(id: record.id, title: title, provenance: record.provenance)
        }
    }

    /// A picture's record in `library.json`. Its other fields (source, license evidence,
    /// checksum, …) are for the people who audit the library.
    private struct Record: Decodable {
        let id: String
        /// English; the catalog's `sample.<id>` translates it.
        let title: String
        let provenance: Provenance

        private enum CodingKeys: String, CodingKey { case id, title }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            provenance = try Provenance(from: decoder)
        }
    }
}
