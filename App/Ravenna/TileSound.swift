import AVFoundation

/// The sound of tiles going in: Paint by Moonlight's tune (`Melody` in MosaicKit), a note per
/// tile, each a clink in the tile's own material (`Voice`: synthesized, no recordings, so nothing
/// to license). A paint used up plays a little rising arpeggio from the latest note, a finished
/// wall the finale, both after Paint by Moonlight's `SoundPlayer` (pbordjadze/paint-by-number at
/// 805b7ff). Ambient: the silent switch silences it and other audio keeps playing.
final class TileSound {
    static let shared = TileSound()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    /// Each voice's notes in each mode, made the first time they're needed.
    private var made: [String: [AVAudioPCMBuffer]] = [:]
    private var built = false
    private var melody = Melody()
    /// When the last tile asked for a note, played or not, and when one last sounded.
    private var lastAsked = Date.distantPast, lastPlayed = Date.distantPast

    /// The tile's note: the tune's next, unless a row is going in faster than notes can sound
    /// (one every 40 ms at most), or `row` says one note a row. `size` 0...1, the tile's weight.
    func play(_ voice: Voice, size: Double, mode: Melody.Mode, row: RowSound) {
        let now = Date.now
        defer { lastAsked = now }
        switch row {
        case .run: guard now.timeIntervalSince(lastPlayed) > 0.04 else { return }
        // A row's tiles come 45 ms apart; a tile after a pause begins a new row.
        case .note: guard now.timeIntervalSince(lastAsked) > 0.09 else { return }
        }
        // A quick run is a patter, softer than tiles set one at a time.
        let quick = now.timeIntervalSince(lastPlayed) < 0.12
        lastPlayed = now
        guard start() else { return }
        let note = melody.next(at: now)
        let volume = Float(0.3 + 0.3 * min(max(size, 0), 1)) * (quick ? 0.7 : 1)
        sound(notes(voice, mode)[note.index], volume: volume)
    }

    /// A paint used up: a little rising arpeggio from the tune's latest note, after `delay` s.
    func paintDone(_ voice: Voice, mode: Melody.Mode, delay: TimeInterval) {
        guard start() else { return }
        let tones = notes(voice, mode), root = min(melody.latest, tones.count - 5)
        let step = mode == .major ? 0.085 : 0.12
        for (k, interval) in [0, 2, 4].enumerated() {
            sound(tones[root + interval], volume: 0.45, delay: delay + step * Double(k))
        }
    }

    /// The wall set, after `delay` s, in gold. Major: a run up every note to an open chord. Minor: a
    /// slower run down that settles on a low chord.
    func finished(mode: Melody.Mode, delay: TimeInterval) {
        guard start() else { return }
        let tones = notes(.gold, mode)
        switch mode {
        case .major:
            for i in tones.indices { sound(tones[i], volume: 0.34 + 0.015 * Float(i), delay: delay + 0.07 * Double(i)) }
            for i in [5, 7, 9, 11] { sound(tones[i], volume: 0.4, delay: delay + 0.07 * Double(tones.count) + 0.12) }
        case .minor:
            for (k, i) in tones.indices.reversed().enumerated() {
                sound(tones[i], volume: 0.36 - 0.008 * Float(k), delay: delay + 0.1 * Double(k))
            }
            for i in [0, 1, 3, 4] { sound(tones[i], volume: 0.38, delay: delay + 0.1 * Double(tones.count) + 0.15) }
        }
    }

    private func notes(_ voice: Voice, _ mode: Melody.Mode) -> [AVAudioPCMBuffer] {
        let key = "\(voice)-\(mode)"
        if let notes = made[key] { return notes }
        let notes = mode.scale.compactMap { buffer(voice.clink(frequency: $0, rate: format.sampleRate)) }
        made[key] = notes
        return notes
    }

    private func start() -> Bool {
        if !built {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            // Enough voices for the finale's run and chord to ring together.
            for _ in 0..<16 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: format)
                players.append(p)
            }
            engine.prepare()
            built = true
        }
        // After an interruption or a route change the engine stops; start it again.
        if !engine.isRunning {
            try? engine.start()
            if engine.isRunning { players.forEach { $0.play() } }
        }
        return engine.isRunning
    }

    private func sound(_ buffer: AVAudioPCMBuffer, volume: Float, delay: TimeInterval = 0) {
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = volume
        if delay > 0, let node = p.lastRenderTime, let time = p.playerTime(forNodeTime: node) {
            let at = AVAudioTime(sampleTime: time.sampleTime + AVAudioFramePosition(delay * format.sampleRate), atRate: format.sampleRate)
            p.scheduleBuffer(buffer, at: at, options: [], completionHandler: nil)
        } else {
            p.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        }
        if !p.isPlaying { p.play() }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = b.floatChannelData?[0] else { return nil }
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}
