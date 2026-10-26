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
        defaults.string(forKey: oneFingerKey).flatMap(OneFinger.init(rawValue:)) ?? .lays
    }

    static func rowSound(in defaults: UserDefaults = .standard) -> RowSound {
        defaults.string(forKey: rowSoundKey).flatMap(RowSound.init(rawValue:)) ?? .run
    }
}

/// What one finger does on the canvas.
nonisolated enum OneFinger: String, CaseIterable, Sendable {
    /// v0's way, the default (the design page): a drag lays a row at once, and two fingers move
    /// and zoom.
    case lays
    /// Paint by Moonlight's way: one finger moves the wall, a tap sets a tile, and a press then a
    /// drag lays a row.
    case moves
}

/// What a row laid with a drag sounds like.
nonisolated enum RowSound: String, CaseIterable, Sendable {
    /// A quick run of the tune, a note a tile.
    case run
    /// One note for the row.
    case note
}

extension Finish {
    /// The finish's name in Settings (MosaicKit's own `name` is the sketchbook's).
    var title: String {
        switch self {
        case .flat: String(localized: "finish.flat", defaultValue: "Light Grout",
                           comment: "Choice of Settings › Finish: flat tiles on light grout, a thin dark edge")
        case .bed: String(localized: "finish.bed", defaultValue: "Painted Bed",
                          comment: "Choice of Settings › Finish: flat tiles on a bed painted in the colours of the tiles round each joint")
        case .material: String(localized: "finish.material", defaultValue: "Glass and Stone",
                               comment: "Choice of Settings › Finish: tiles with a lit edge, glass that glints and matte stone in faces")
        }
    }
}

extension OneFinger {
    var name: String {
        switch self {
        case .lays: String(localized: "oneFinger.lays", defaultValue: "Lays Tiles",
                           comment: "Choice of Settings › One Finger: a drag lays a row of tiles, two fingers move the mosaic")
        case .moves: String(localized: "oneFinger.moves", defaultValue: "Moves the Mosaic",
                            comment: "Choice of Settings › One Finger: a drag moves the mosaic, a press then a drag lays a row")
        }
    }
}

extension RowSound {
    var name: String {
        switch self {
        case .run: String(localized: "rowSound.run", defaultValue: "A Run of the Tune",
                          comment: "Choice of Settings › Row Sound: each tile laid in a row plays the tune's next note")
        case .note: String(localized: "rowSound.note", defaultValue: "One Note",
                           comment: "Choice of Settings › Row Sound: a row laid in one stroke plays one note")
        }
    }
}
