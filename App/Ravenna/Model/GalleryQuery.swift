import Foundation

/// Which paintings the gallery's Show menu lists.
nonisolated enum GalleryFilter: String, CaseIterable, Sendable {
    case all
    case favorites
}

/// What the gallery shows: the Show filter with the search field's text on top of it.
nonisolated struct GalleryQuery: Equatable, Sendable {
    var filter: GalleryFilter = .all
    var search = ""

    /// Whether anything is hidden: the painter is looking at a selection, not the whole library.
    var isActive: Bool { filter != .all || isSearching }

    /// Text that narrows the list (a blank or punctuation-only field shows everything).
    var isSearching: Bool { !TitleSearch.words(in: search).isEmpty }

    func includes(_ artwork: Artwork) -> Bool {
        (filter == .all || artwork.isFavorite) && TitleSearch.matches(artwork.title, query: search)
    }
}

/// The gallery's search: every word of the query must start a word of the title, ignoring case,
/// diacritics and character width ("ba" and "bá" find "Red Barn"; "arn" does not).
nonisolated enum TitleSearch {
    static func matches(_ title: String, query: String) -> Bool {
        let wanted = words(in: query)
        guard !wanted.isEmpty else { return true }
        let available = words(in: title)
        return wanted.allSatisfy { prefix in available.contains { $0.hasPrefix(prefix) } }
    }

    /// The folded, lowercase words of `text`; anything that is not a letter or digit separates them.
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
