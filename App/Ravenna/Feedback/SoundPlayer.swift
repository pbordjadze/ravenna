import AVFoundation
import Foundation
import os

/// Soft, musical feedback sounds, synthesized the first time they're needed (when a painting
/// screen first appears, or at the first sound; no audio assets).
///
/// Painting plays one tune (`PaintingMelody`, kept by `FeedbackEngine`, which hands over each
/// note), a note per fill whatever the color, on a pentatonic scale so its notes can never
/// clash. Each sky (`Sky`) has its own voice: by Sun a
/// bright kalimba, by Moon a celesta-like bell on the same five notes, lower and minor, with a
/// quiet twinkle where a phrase comes to rest; finishing a color or the painting plays the
/// sky's own flourish. A sky's notes are synthesized the first time it plays. Uses the ambient
/// session category: it mixes with the user's music and respects the silent switch.
///
/// The engine and everything below live on `queue`, which plays the sounds in the order they're
/// asked for: starting the engine blocks its caller, on CI's simulator long enough that a
/// painting screen starting it on the main thread stopped answering.
nonisolated final class SoundPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pbordjadze.paintbynumber.sounds", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    /// Each sky's notes, once it has played (`notes(of:)`).
    private var made: [Sky: [AVAudioPCMBuffer]] = [:]
    /// The Moon's twinkles: each of its notes an octave up.
    private var twinkles: [AVAudioPCMBuffer] = []
    private var thud: AVAudioPCMBuffer?
    private var isBuilt = false
    private var isSetUp = false
    private let clock = ContinuousClock()

    /// Sun: D major pentatonic over two octaves from D4, a tone above the C the app first played.
    static let sunScale: [Double] = [293.66, 329.63, 369.99, 440.00, 493.88, 587.33, 659.26, 739.99, 880.00, 987.77, 1174.66, 1318.51]
    /// Moon: the same five notes as their minor, from the B below, so the tune sits lower.
    static let moonScale: [Double] = [246.94] + sunScale.dropLast()

    static func scale(of sky: Sky) -> [Double] {
        switch sky {
        case .sun: sunScale
        case .moon: moonScale
        }
    }

    /// The bell rings longer than the kalimba, so it plays a little softer.
    private static func level(of sky: Sky) -> Float {
        switch sky {
        case .sun: 1
        case .moon: 0.85
        }
    }

    /// Starts the engine and synthesizes `sky`'s notes, so the first stroke isn't late.
    func prepare(sky: Sky) {
        queue.async { [self] in
            guard setUpIfNeeded() else { return }
            _ = notes(of: sky)
        }
    }

    /// Plays the tune's `note`, and the Moon's twinkle where its phrase rests. `velocity` 0…1.
    func paint(_ note: PaintingMelody.Note, velocity: Float) {
        queue.async { [self] in
            guard setUpIfNeeded() else { return }
            let volume = (0.18 + 0.22 * min(max(velocity, 0), 1)) * Self.level(of: note.sky)
            play(notes(of: note.sky)[note.index], volume: volume)
            if note.sky == .moon, note.endsPhrase {
                play(twinkle(note.index), volume: volume * 0.35, delay: 0.12)
            }
        }
    }

    func reject() {
        queue.async { [self] in
            guard setUpIfNeeded(), let thud else { return }
            play(thud, volume: 0.35)
        }
    }

    /// A little rising arpeggio from the tune's latest note `latest`, in `sky`; the Moon's is slower.
    func colorComplete(sky: Sky, from latest: Int) {
        queue.async { [self] in
            guard setUpIfNeeded() else { return }
            let tones = notes(of: sky)
            let root = min(latest, tones.count - 5)
            let (start, step) = sky == .sun ? (0.12, 0.085) : (0.14, 0.12)
            for (k, interval) in [0, 2, 4].enumerated() {
                play(tones[root + interval], volume: 0.3 * Self.level(of: sky), delay: start + step * Double(k))
            }
        }
    }

    /// The finale in `sky`. Sun: a bright run up every note to an open, sunlit chord. Moon: a
    /// slower, softer run down that settles on a warm low chord, one star left ringing above it.
    func celebrate(sky: Sky) {
        queue.async { [self] in
            guard setUpIfNeeded() else { return }
            let tones = notes(of: sky)
            switch sky {
            case .sun:
                for i in 0..<tones.count {
                    play(tones[i], volume: 0.22 + 0.01 * Float(i), delay: 0.07 * Double(i))
                }
                for i in [5, 7, 9, 11] {
                    play(tones[i], volume: 0.28, delay: 0.07 * Double(tones.count) + 0.12)
                }
            case .moon:
                let level = Self.level(of: .moon)
                for (k, i) in tones.indices.reversed().enumerated() {
                    play(tones[i], volume: (0.24 - 0.005 * Float(k)) * level, delay: 0.1 * Double(k))
                }
                let chord = 0.1 * Double(tones.count) + 0.15
                for i in [0, 1, 3, 4] {
                    play(tones[i], volume: 0.26 * level, delay: chord)
                }
                play(twinkle(5), volume: 0.2, delay: chord + 0.35)
            }
        }
    }

    // MARK: Engine (on `queue`)

    private func setUpIfNeeded() -> Bool {
        if isSetUp {
            if !engine.isRunning { try? engine.start() }
            return engine.isRunning
        }
        let start = clock.now
        // The graph is built once: a start that fails (a call holding the audio session) is retried
        // by the next sound without attaching another ten nodes.
        if !isBuilt {
            for _ in 0..<10 {
                let voice = AVAudioPlayerNode()
                engine.attach(voice)
                engine.connect(voice, to: engine.mainMixerNode, format: format)
                voices.append(voice)
            }
            engine.mainMixerNode.outputVolume = 0.8
            thud = buffer(ToneSynth.thud(sampleRate: format.sampleRate))
            isBuilt = true
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.prepare()
            try engine.start()
            for voice in voices { voice.play() }
            isSetUp = true
            let took = clock.now - start
            Log.feedback.notice("Sounds ready in \(String(describing: took), privacy: .public)")
            return true
        } catch {
            Log.feedback.error("Sounds unavailable: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// `sky`'s notes, synthesized the first time they're asked for.
    private func notes(of sky: Sky) -> [AVAudioPCMBuffer] {
        if let notes = made[sky] { return notes }
        let rate = format.sampleRate
        let notes = Self.scale(of: sky).map { frequency in
            buffer(sky == .sun ? ToneSynth.kalimba(frequency: frequency, sampleRate: rate)
                               : ToneSynth.celesta(frequency: frequency, sampleRate: rate))
        }
        made[sky] = notes
        return notes
    }

    /// The twinkle an octave above the Moon's note `index`.
    private func twinkle(_ index: Int) -> AVAudioPCMBuffer {
        if twinkles.isEmpty {
            twinkles = Self.moonScale.map { buffer(ToneSynth.twinkle(frequency: 2 * $0, sampleRate: format.sampleRate)) }
        }
        return twinkles[index]
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float, delay: TimeInterval = 0) {
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = volume
        if delay > 0, let nodeTime = voice.lastRenderTime, let playerTime = voice.playerTime(forNodeTime: nodeTime) {
            let start = AVAudioTime(
                sampleTime: playerTime.sampleTime + AVAudioFramePosition(delay * format.sampleRate),
                atRate: format.sampleRate)
            voice.scheduleBuffer(buffer, at: start, options: [], completionHandler: nil)
        } else {
            voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        }
        if !voice.isPlaying { voice.play() }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
