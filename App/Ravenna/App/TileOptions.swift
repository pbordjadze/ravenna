import Foundation
import MosaicKit

/// Ravenna's choices for setting tiles, kept as options until Paul narrows them (CLAUDE.md:
/// "where a creative choice diverges just make it an option in the app for now"). Stored in
/// UserDefaults under v0's keys, so v0's choices carry over; read live, so a change shows on the
/// next frame or tile. Settings shows them (the engine track's Settings).
nonisolated enum TileOptions {
    /// How set tiles look (MosaicKit's `Finish`): v0's `Library.finish`, glass and stone by default.
    static let finishKey = "finish"
    /// What one finger does on the canvas (`OneFinger`).
    static let oneFingerKey = "oneFinger"
    /// What a row laid with a drag sounds like (`RowSound`).
    static let rowSoundKey = "rowSound"

    static func finish(in defaults: UserDefaults = .standard) -> Finish {
        defaults.string(forKey: finishKey).flatMap(Finish.init(rawValue:)) ?? .material
    }

    static func oneFinger(in defaults: UserDefaults = .standard) -> OneFinger {
        defaults.string(forKey: oneFingerKey).flatMap(OneFinger.init(rawValue:)) ?? .moves
    }

    static func rowSound(in defaults: UserDefaults = .standard) -> RowSound {
        defaults.string(forKey: rowSoundKey).flatMap(RowSound.init(rawValue:)) ?? .run
    }
}

/// What one finger does on the canvas.
nonisolated enum OneFinger: String, CaseIterable, Sendable {
    /// Paint by Moonlight's way, the default: one finger moves the wall, a tap sets a tile, and a
    /// press then a drag lays a row.
    case moves
    /// v0's way: a drag lays a row at once, and two fingers move and zoom.
    case lays
}

/// What a row laid with a drag sounds like.
nonisolated enum RowSound: String, CaseIterable, Sendable {
    /// A quick run of the tune, a note a tile.
    case run
    /// One note for the row.
    case note
}
