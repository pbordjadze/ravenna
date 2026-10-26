import Foundation

/// The tune painting plays: each fill plays the next note, whatever color was painted, so
/// any painting order sounds like the same gentle melody. Sun and Moon sing the same tune, each
/// on its own scale (`SoundPlayer.scale(of:)`), and the sky turns only where a phrase begins, so
/// a change of sky never cuts one; the fill's stars turn with it (`FeedbackEngine`).
nonisolated struct PaintingMelody {
    /// Indices into a sky's scale (five notes over two octaves and more): six eight-note phrases
    /// that rise, answer and settle back home on the scale's first note, then start over.
    static let tune: [Int] = [
        2, 3, 4, 3, 2, 1, 0, 1,
        2, 3, 4, 5, 4, 3, 2, 3,
        4, 5, 6, 7, 6, 5, 4, 5,
        6, 7, 8, 7, 6, 5, 4, 3,
        2, 3, 4, 3, 2, 1, 2, 3,
        5, 4, 3, 2, 1, 2, 1, 0,
    ]
    static let phraseLength = 8
    /// After a pause this long the tune picks up at the start of its next phrase, so coming
    /// back to a painting doesn't resume mid-phrase.
    static let breath: Duration = .seconds(5)

    struct Note: Equatable, Sendable {
        let sky: Sky
        /// Its place on the sky's scale.
        let index: Int
        /// The last note of its phrase, where the phrase comes to rest (the Moon twinkles there).
        let endsPhrase: Bool
    }

    private(set) var position = 0
    /// The most recently played note (the tune's first before any).
    private(set) var latest = Self.tune[0]
    /// The sky the tune is in, from its first note on.
    private(set) var sky: Sky?
    private var lastPlayed: ContinuousClock.Instant?

    /// The sky a fill's note at `now` plays in, with `requested` the sky of the moment, without
    /// playing it: the tune takes the requested sky at its first note and wherever a phrase begins.
    func skyOfNote(at now: ContinuousClock.Instant, under requested: Sky) -> Sky {
        place(at: now).isMultiple(of: Self.phraseLength) ? requested : sky ?? requested
    }

    /// The note to play for a fill at `now`, with `requested` the sky of the moment.
    mutating func next(at now: ContinuousClock.Instant, under requested: Sky) -> Note {
        let current = skyOfNote(at: now, under: requested)
        position = place(at: now)
        sky = current
        lastPlayed = now
        latest = Self.tune[position]
        let note = Note(sky: current, index: latest, endsPhrase: (position + 1).isMultiple(of: Self.phraseLength))
        position = (position + 1) % Self.tune.count
        return note
    }

    /// Where the tune stands for a fill at `now`: after a breath, the start of its next phrase.
    private func place(at now: ContinuousClock.Instant) -> Int {
        guard let lastPlayed, now - lastPlayed >= Self.breath, !position.isMultiple(of: Self.phraseLength) else {
            return position
        }
        return (position / Self.phraseLength + 1) * Self.phraseLength % Self.tune.count
    }
}
