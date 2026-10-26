import Foundation
import PaintCore

/// Turns painting events into haptics and sound. One shared instance; attach each
/// `PaintingSession` when its screen appears.
///
/// Preferences (read live, set from Settings): `SettingsKey.haptics`, `SettingsKey.sounds`
/// (both default on), and `SettingsKey.sky`, whose sky of the moment picks the sounds.
final class FeedbackEngine {
    static let shared = FeedbackEngine()

    private let haptics = HapticsPlayer()
    private let sounds = SoundPlayer()

    private final class AttachedSession {
        weak var session: PaintingSession?
        init(_ session: PaintingSession) { self.session = session }
    }

    /// Weak, not by `ObjectIdentifier`: a freed session's address can come back as a new one's.
    private var attached: [AttachedSession] = []

    /// The tune, kept here rather than with the sounds so the canvas can ask which sky the coming
    /// fill is in (`skyOfComingFill`): the fill's sparkles turn to stars where the music turns,
    /// as a phrase begins. It plays on with the sounds off.
    private var melody = PaintingMelody()
    private var lastNote: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    /// How long the canvas animates a fill, so the haptic swell can match it. The canvas may
    /// update this per paint.
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
        if hapticsEnabled { haptics.prepare() }
        if soundsEnabled { sounds.prepare(sky: Sky.current()) }
    }

    /// The sky the next fill plays in: the tune's own until its next phrase begins (or a pause
    /// lets it turn), then the sky of the hour.
    func skyOfComingFill() -> Sky {
        melody.skyOfNote(at: clock.now, under: Sky.current())
    }

    /// Selection changes and other UI detents.
    func selectionChanged() {
        if hapticsEnabled { haptics.tick() }
    }

    /// A line in Refine closed off an area of its own: a soft tap, smaller than a fill's.
    func areaMade() {
        if hapticsEnabled { haptics.paint(strength: 0.3, duration: 0.12) }
    }

    private func handle(_ event: PaintEvent, in session: PaintingSession) {
        let hapticsOn = hapticsEnabled, soundsOn = soundsEnabled
        let sky = melody.sky ?? Sky.current()
        switch event {
        case let .painted(regions, _):
            // Perceived size of what was painted, relative to the canvas.
            let area = regions.reduce(Float(0)) { $0 + session.template.regions[$1].area }
            let canvas = Float(max(1, session.template.width * session.template.height))
            let size = min(1, (area / canvas).squareRoot() * 6)
            if hapticsOn { haptics.paint(strength: size, duration: fillDuration) }
            // At most a note every 40 ms: a stroke's fills come faster than notes can sound.
            let now = clock.now
            if lastNote.map({ now - $0 >= .milliseconds(40) }) ?? true {
                lastNote = now
                let note = melody.next(at: now, under: Sky.current())
                if soundsOn { sounds.paint(note, velocity: 0.35 + 0.65 * size) }
            }
        case .rejected:
            if hapticsOn { haptics.reject() }
            if soundsOn { sounds.reject() }
        case .colorCompleted where session.isComplete:
            // The fill that finishes the painting finishes a color too: the painting's
            // celebration is the one finale.
            break
        case .colorCompleted:
            if hapticsOn { haptics.colorComplete() }
            if soundsOn { sounds.colorComplete(sky: sky, from: melody.latest) }
        case .artworkCompleted:
            if hapticsOn { haptics.celebrate() }
            if soundsOn { sounds.celebrate(sky: sky) }
        case .undone:
            if hapticsOn { haptics.tick() }
        case .strokeEnded, .hintShown, .missedSmallArea:
            // A near miss follows the rejected buzz already felt; the hint moves the camera.
            break
        }
    }
}
