import AVFoundation

// A two-pole bandpass resonator (RBJ cookbook, constant 0 dB peak gain).
// Excited by noise, it rings at its centre frequency — the core of the
// keycap/case "body" sound.
private struct Biquad {
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(freq: Double, q: Double, sampleRate: Double) {
        let w0 = 2.0 * .pi * min(freq, sampleRate * 0.45) / sampleRate
        let alpha = sin(w0) / (2.0 * max(q, 0.1))
        let a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = (-2.0 * cos(w0)) / a0
        a2 = (1.0 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

// Procedural click synthesis. No recorded samples anywhere in Clonk.
enum Synth {
    static let sampleRate: Double = 44_100

    static func render(_ theme: Theme, isRelease: Bool, pitch: Double) -> AVAudioPCMBuffer {
        let sr = sampleRate
        let bright = isRelease ? theme.releaseBright : 1.0
        let totalDecay = (isRelease ? theme.totalDecay * 0.55 : theme.totalDecay)
        let clickGain = theme.clickGain * (isRelease ? 0.6 : 1.0)

        let duration = totalDecay + 0.012
        let count = Int(duration * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let out = buffer.floatChannelData![0]

        // Body resonators — pitch and the release brightness shift their tuning.
        var res1 = Biquad(freq: theme.res1Freq * pitch * bright, q: theme.res1Q, sampleRate: sr)
        var res2 = Biquad(freq: theme.res2Freq * pitch * bright, q: theme.res2Q, sampleRate: sr)

        let exciteTau = max(theme.exciteDecay, 0.0005) / 4.0
        let masterTau = totalDecay / 4.0
        let clickTau = theme.clickDecay / 4.0

        // One-pole high-pass for the bright contact transient.
        let hpCoeff = exp(-2.0 * .pi * theme.clickHighpass / sr)
        var hpX = 0.0, hpY = 0.0
        var rng = SystemRandomNumberGenerator()

        var raw = [Double](repeating: 0, count: count)
        var peak = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let white = Double.random(in: -1...1, using: &rng)

            let excite = white * exp(-t / exciteTau)
            let body = res1.process(excite) * theme.res1Gain
                     + res2.process(excite) * theme.res2Gain

            hpY = hpCoeff * (hpY + white - hpX)
            hpX = white
            let click = hpY * exp(-t / clickTau) * clickGain

            var s = (body * 3.2 + click) * exp(-t / masterTau)
            let ramp = 0.0005
            if t < ramp { s *= t / ramp }
            raw[i] = s
            peak = max(peak, abs(s))
        }

        // Normalise to a consistent loudness so themes differ in character,
        // not volume; release sounds are then trimmed quieter than the press.
        let target = theme.gain * (isRelease ? theme.releaseGain : 1.0)
        let norm = peak > 1e-6 ? target / peak : 0
        for i in 0..<count {
            out[i] = Float(tanh(raw[i] * norm * 1.1))
        }
        return buffer
    }
}

// Pre-rendered click variants for one theme. Rendering happens once when the
// theme changes; keypresses just pick a ready buffer (cheap, real-time).
struct ThemeBank {
    let press: [AVAudioPCMBuffer]
    let release: [AVAudioPCMBuffer]
    let bigPress: [AVAudioPCMBuffer]
    let bigRelease: [AVAudioPCMBuffer]
    let hasRelease: Bool

    static func build(from theme: Theme, basePitch: Double = 1.0) -> ThemeBank {
        func variants(isRelease: Bool, bigKey: Bool) -> [AVAudioPCMBuffer] {
            let base = basePitch * (bigKey ? 0.8 : 1.0)
            let jitters: [Double] = [-1, -0.5, 0, 0.5, 1]
            return jitters.map { j in
                let pitch = base * (1.0 + j * theme.pitchJitter)
                return Synth.render(theme, isRelease: isRelease, pitch: pitch)
            }
        }
        return ThemeBank(
            press: variants(isRelease: false, bigKey: false),
            release: variants(isRelease: true, bigKey: false),
            bigPress: variants(isRelease: false, bigKey: true),
            bigRelease: variants(isRelease: true, bigKey: true),
            hasRelease: theme.releaseGain > 0.001)
    }

    func pressBuffer(big: Bool) -> AVAudioPCMBuffer {
        (big ? bigPress : press).randomElement()!
    }
    func releaseBuffer(big: Bool) -> AVAudioPCMBuffer {
        (big ? bigRelease : release).randomElement()!
    }
}
