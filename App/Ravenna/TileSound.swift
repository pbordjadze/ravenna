import AVFoundation

/// The sound of tiles going in. Synthesized when first needed (`Voice` in MosaicKit: noise and
/// decaying partials, no recordings, so nothing to license), four variants of each voice so a row
/// doesn't ring the same note. Ambient: the silent switch silences it and other audio keeps playing.
final class TileSound {
    static let shared = TileSound()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Voice: [AVAudioPCMBuffer]] = [:]
    private var ready = false
    private var last = Date.distantPast

    /// Plays a voice; `loudness` 0...1. Thinned to keep a fast row a patter.
    func play(_ voice: Voice, variant: Int, loudness: Float = 0.8) {
        let now = Date.now
        guard now.timeIntervalSince(last) > 0.035 else { return }
        last = now
        guard start(), let all = buffers[voice], !all.isEmpty else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = loudness
        p.scheduleBuffer(all[variant % all.count], at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    private func start() -> Bool {
        if !ready {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            for v in Voice.allCases { buffers[v] = (0..<4).compactMap { buffer(v.samples(variant: $0, rate: format.sampleRate)) } }
            for _ in 0..<6 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: engine.mainMixerNode, format: format)
                players.append(p)
            }
            engine.prepare()
            ready = true
        }
        // After an interruption or a route change the engine stops; start it again.
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = b.floatChannelData?[0] else { return nil }
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}
