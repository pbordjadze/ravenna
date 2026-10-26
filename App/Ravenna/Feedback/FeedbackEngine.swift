import Foundation
import MosaicKit
import PaintCore

/// Turns painting events into haptics and sound. One shared instance; attach each
/// `PaintingSession` when its screen appears.
///
/// Ravenna's seam: tiles clink (`TileSound`, Paint by Moonlight's tune in glass, stone and gold)
/// and tap the finger (`TileTouch`) as each touches the bed, in place of Paint by Moonlight's
/// synthesized melody and Core Haptics patterns. A painting that isn't a mosaic sounds as glass.
///
/// Preferences (read live, set from Settings): `SettingsKey.haptics`, `SettingsKey.sounds`
/// (both default on), `SettingsKey.sky`, whose sky of the moment puts the tune in major (Sun) or
/// minor (Moon), and `TileOptions.rowSound`.
final class FeedbackEngine {
    static let shared = FeedbackEngine()

    private let touch = TileTouch()
    private let sounds = TileSound()

    private final class AttachedSession {
        weak var session: PaintingSession?
        init(_ session: PaintingSession) { self.session = session }
    }

    /// Weak, not by `ObjectIdentifier`: a freed session's address can come back as a new one's.
    private var attached: [AttachedSession] = []

    /// When each region of the coming fill touches the bed, in seconds from now, in its order: the
    /// canvas sets it as it starts the tiles settling (`CanvasView.setTiles`), before the sounds
    /// hear of the fill. Empty: at once.
    var tileContacts: [TimeInterval] = []
    /// How long the canvas animates a fill of paint (demos wait for it).
    var fillDuration: TimeInterval = 0.4

    private var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? SettingsDefault.haptics }
    private var soundsEnabled: Bool { UserDefaults.standard.object(forKey: SettingsKey.sounds) as? Bool ?? SettingsDefault.sounds }

    private init() {}

    /// Plays a session's events, once however often its screen appears, and warms up the
    /// engines so the first stroke isn't late.
    func attach(to session: PaintingSession) {
        attached.removeAll { $0.session == nil }
        guard !attached.contains(where: { $0.session === session }) else { return }
        attached.append(AttachedSession(session))
        session.onEvent { [weak self, weak session] event in
            guard let self, let session else { return }
            self.handle(event, in: session)
        }
        prepare()
    }

    private func prepare() {
        if hapticsEnabled { touch.prepare() }
        if soundsEnabled { sounds.prepare(mode: Self.mode()) }
    }

    /// The sky the next fill plays in (a painting that isn't a mosaic pops stars by Moon).
    func skyOfComingFill() -> Sky { Sky.current() }

    /// The tune's mode: the Sun's major or the Moon's minor.
    private static func mode() -> Melody.Mode { Sky.current() == .moon ? .minor : .major }

    /// Selection changes and other UI detents.
    func selectionChanged() {
        if hapticsEnabled { touch.detent() }
    }

    /// A line in Refine closed off an area of its own: a soft tap, smaller than a fill's.
    func areaMade() {
        if hapticsEnabled { touch.set(.stone, size: 0.2) }
    }

    /// When the latest fill's last tile touched the bed (s from then): a flourish follows its note.
    private var lastContact: TimeInterval = 0
    /// The last tile's note first (it sounds as the tile touches the bed), then a flourish from it.
    private var flourishDelay: TimeInterval { lastContact + 0.12 }

    private func handle(_ event: PaintEvent, in session: PaintingSession) {
        let hapticsOn = hapticsEnabled, soundsOn = soundsEnabled
        let mode = Self.mode()
        switch event {
        case let .painted(regions, _):
            let row = TileOptions.rowSound()
            for (k, r) in regions.enumerated() {
                let voice: Voice, size: Double
                if let wall = session.wall, wall.isTile(r) {
                    voice = wall.voices[r]
                    size = Double(wall.weights[r])
                } else {
                    // Perceived size of what was painted, relative to the canvas.
                    let canvas = Float(max(1, session.template.width * session.template.height))
                    voice = .glass
                    size = Double(min(1, (session.template.regions[r].area / canvas).squareRoot() * 6))
                }
                let delay = k < tileContacts.count ? tileContacts[k] : 0
                if soundsOn { sounds.play(voice, size: size, mode: mode, row: row, after: delay) }
                if hapticsOn { touch.set(voice, size: size, after: delay) }
            }
            // Spent: a fill the canvas didn't time plays at once.
            lastContact = tileContacts.last ?? 0
            tileContacts = []
        case .rejected:
            if hapticsOn { touch.miss() }
            if soundsOn { sounds.miss() }
        case .colorCompleted where session.isComplete:
            // The tile that finishes the painting finishes a paint too: the painting's
            // celebration is the one finale.
            break
        case .colorCompleted:
            if soundsOn { sounds.paintDone(.glass, mode: mode, delay: flourishDelay) }
            if hapticsOn { touch.paintDone(delay: flourishDelay, step: TileSound.step(mode)) }
        case .artworkCompleted:
            if soundsOn { sounds.finished(mode: mode, delay: flourishDelay) }
            if hapticsOn { touch.finished() }
        case .undone:
            if hapticsOn { touch.detent() }
        case .strokeEnded, .hintShown, .missedSmallArea:
            // A near miss follows the "no" already felt; the hint moves the camera.
            break
        }
    }
}
