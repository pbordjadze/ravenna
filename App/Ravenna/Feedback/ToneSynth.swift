import Foundation
import PaintCore

/// Tiny additive synthesizer for the feedback sounds.
nonisolated enum ToneSynth {
    /// The Sun's voice, a plucked tine: fundamental with a bright, fast-decaying inharmonic
    /// partial and a soft "wet" noise onset (the brush touching the canvas). The kalimba the app
    /// first played, a little brighter and lighter: a stronger octave and tine, a shorter ring.
    static func kalimba(frequency f: Double, sampleRate sr: Double) -> [Float] {
        let length = 0.75, fade = 0.05
        let n = Int(sr * length)
        var out = [Float](repeating: 0, count: n)
        var noise = SplitMix64(seed: UInt64(f * 1000))
        var lowpassed: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            let attack = min(1, t / 0.003)
            let body = sin(2 * .pi * f * t) * exp(-t * 6.5)
            let octave = 0.24 * sin(2 * .pi * 2 * f * t) * exp(-t * 10)
            let tine = 0.26 * sin(2 * .pi * 5.4 * f * t) * exp(-t * 30)
            let bits: UInt64 = noise.next()
            lowpassed += 0.25 * (Double(bits >> 11) / Double(1 << 53) * 2 - 1 - lowpassed)
            let brush = 0.08 * lowpassed * exp(-t * 45)
            let tail = min(1, (length - t) / fade)
            out[i] = Float((attack * (body + octave + tine) + brush) * tail) * 0.55
        }
        return out
    }

    /// The Moon's voice, a celesta-like bell: a warm fundamental and octave under the struck
    /// bar's inharmonic ring, a soft felt onset, a longer ring than the kalimba. A little uneven,
    /// as if made by hand: each note is tuned up to about 3 cents off and struck a little harder
    /// or softer, the same at every launch.
    static func celesta(frequency f0: Double, sampleRate sr: Double) -> [Float] {
        let length = 1.6, fade = 0.25
        let n = Int(sr * length)
        var out = [Float](repeating: 0, count: n)
        var noise = SplitMix64(seed: UInt64(f0 * 1000) ^ 0x6D6F_6F6E)
        func unit() -> Double { Double(noise.next() >> 11) / Double(1 << 53) * 2 - 1 }
        let f = f0 * (1 + 0.0018 * unit())
        let strike = 1 + 0.12 * unit()
        var lowpassed: Double = 0
        for i in 0..<n {
            let t = Double(i) / sr
            let attack = min(1, t / 0.004)
            let body = sin(2 * .pi * f * t) * exp(-t * 2.4)
            let octave = 0.26 * sin(2 * .pi * 2 * f * t) * exp(-t * 4.5)
            let ring = strike * (0.14 * sin(2 * .pi * 2.756 * f * t) * exp(-t * 11)
                + 0.05 * sin(2 * .pi * 5.404 * f * t) * exp(-t * 24))
            lowpassed += 0.2 * (unit() - lowpassed)
            let felt = 0.06 * lowpassed * exp(-t * 70)
            let tail = min(1, (length - t) / fade)
            out[i] = Float((attack * (body + octave + ring) + felt) * tail) * 0.5
        }
        return out
    }

    /// A star's twinkle over the Moon's bell: a quiet, pure ping, struck softly and gone in under
    /// a second.
    static func twinkle(frequency f: Double, sampleRate sr: Double) -> [Float] {
        let length = 0.8, fade = 0.15
        let n = Int(sr * length)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let attack = min(1, t / 0.006)
            let ping = sin(2 * .pi * f * t) * exp(-t * 5) + 0.1 * sin(2 * .pi * 2.756 * f * t) * exp(-t * 18)
            let tail = min(1, (length - t) / fade)
            out[i] = Float(attack * ping * tail) * 0.5
        }
        return out
    }

    /// Muted wooden "thock" for a wrong-color tap.
    static func thud(sampleRate sr: Double) -> [Float] {
        let n = Int(sr * 0.18)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let pitch = 180 * (1 - 0.25 * min(1, t / 0.08))
            let attack = min(1, t / 0.002)
            out[i] = Float(attack * sin(2 * .pi * pitch * t) * exp(-t * 32)) * 0.6
        }
        return out
    }
}
