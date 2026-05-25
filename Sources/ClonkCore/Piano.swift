import AVFoundation

// Piano Mode — every keystroke plays a tuned piano note instead of a click.
// Notes are synthesised additively from inharmonic partials plus a brief
// hammer-strike noise burst. Nothing on disk; banks are rebuilt whenever
// the scale or root note changes.

// A musical scale, shared by the instrument modes (Piano, Guitar). The raw
// values are persisted in profiles, so don't rename the cases.
enum MusicalScale: String, CaseIterable, Identifiable, Codable {
    case majorPentatonic
    case minorPentatonic
    case major
    case minor
    case blues
    case wholeTone
    case chromatic

    var id: String { rawValue }

    var name: String {
        switch self {
        case .majorPentatonic: return "Major Pentatonic"
        case .minorPentatonic: return "Minor Pentatonic"
        case .major: return "Major"
        case .minor: return "Natural Minor"
        case .blues: return "Blues"
        case .wholeTone: return "Whole Tone"
        case .chromatic: return "Chromatic"
        }
    }

    var intervals: [Int] {
        switch self {
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .blues: return [0, 3, 5, 6, 7, 10]
        case .wholeTone: return [0, 2, 4, 6, 8, 10]
        case .chromatic: return Array(0..<12)
        }
    }
}

struct PianoConfig: Codable, Equatable {
    // MIDI note for the home row's first letter (default = C4).
    var rootMidi: Int = 60
    var scale: MusicalScale = .majorPentatonic
    // Release tail length scale (0.4…2.0); shorter = staccato.
    var sustain: Double = 1.0
    // When true, modifier keys (Shift/Cmd/Opt/Ctrl/Fn/CapsLock) play
    // long sustained bass-register notes — a sustain-pedal effect.
    var modifierSustain: Bool = false
}

// macOS Carbon keycodes for modifier keys (Shift, Ctrl, Opt, Cmd, Fn, CapsLock).
enum PianoModifierKeys {
    // (keycode, offset-from-root)
    static let mappings: [(Int, Int)] = [
        (56, -24),  // Left Shift  — two octaves below root
        (60, -24),  // Right Shift
        (59, -19),  // Left Ctrl   — bass 5th below
        (62, -19),  // Right Ctrl
        (58, -17),  // Left Option — bass 4th below
        (61, -17),  // Right Option
        (55, -12),  // Left Cmd    — one octave below
        (54, -12),  // Right Cmd
        (57,  -7),  // CapsLock    — bass 5th
        (63,  -5),  // Fn          — bass 4th
    ]
    static let codes: Set<Int> = Set(mappings.map { $0.0 })
}

// Procedural piano-note rendering. Six inharmonic partials with per-partial
// exponential decay (lower partials ring longer than higher ones, as on a
// real piano), plus a short high-passed noise burst for the hammer attack.
enum PianoSynth {
    static let sampleRate: Double = Synth.sampleRate

    static func render(midi: Int, sustain: Double = 1.0) -> AVAudioPCMBuffer {
        let sr = sampleRate
        let clampedMidi = max(24, min(96, midi))
        let freq = 440.0 * pow(2.0, Double(clampedMidi - 69) / 12.0)

        // Lower notes ring longer. Sustain knob scales the whole thing.
        let baseDur = max(0.7, 2.6 - Double(clampedMidi - 36) * 0.025)
        let dur = baseDur * max(0.4, min(2.0, sustain))
        let count = Int(dur * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let out = buffer.floatChannelData![0]

        let partials = 6
        let amps: [Double] = [1.0, 0.55, 0.32, 0.18, 0.10, 0.06]
        let decayScale = dur * 0.55
        let decays: [Double] = [1.0, 0.82, 0.65, 0.50, 0.40, 0.32].map { $0 * decayScale }
        // Inharmonicity coefficient — piano strings stretch upper partials sharp.
        let inharmB = 0.00035

        var phases = [Double](repeating: 0, count: partials)
        let attack = 0.004
        let release = 0.08

        // Hammer transient: white noise through a one-pole highpass, decaying fast.
        let hpCoeff = exp(-2.0 * .pi * 4500 / sr)
        var hpX = 0.0, hpY = 0.0
        let strikeTau = 0.0028
        var rng = SystemRandomNumberGenerator()

        var raw = [Double](repeating: 0, count: count)
        var peak = 0.0
        let twoPiOverSr = 2.0 * .pi / sr

        for i in 0..<count {
            let t = Double(i) / sr
            var s = 0.0
            for p in 0..<partials {
                let n = Double(p + 1)
                let f = freq * n * sqrt(1.0 + inharmB * n * n)
                phases[p] += twoPiOverSr * f
                let env = exp(-t / decays[p])
                s += sin(phases[p]) * amps[p] * env
            }
            let w = Double.random(in: -1...1, using: &rng)
            hpY = hpCoeff * (hpY + w - hpX); hpX = w
            let strike = hpY * exp(-t / strikeTau) * 0.55
            s += strike

            if t < attack { s *= t / attack }
            let tailStart = Double(count) / sr - release
            if t > tailStart {
                s *= max(0, (Double(count) / sr - t) / release)
            }
            raw[i] = s
            peak = max(peak, abs(s))
        }
        let norm = peak > 1e-6 ? 0.82 / peak : 0
        for i in 0..<count {
            out[i] = Float(tanh(raw[i] * norm))
        }
        return buffer
    }
}

// Holds pre-rendered note buffers for whichever MIDI notes the current
// keymap uses. Rebuild on scale / root / sustain changes.
@MainActor
final class PianoBank {
    private var notes: [Int: AVAudioPCMBuffer] = [:]
    private var sustainedNotes: [Int: AVAudioPCMBuffer] = [:]
    private(set) var keymap: [Int: Int] = [:]
    private var builtConfig: PianoConfig?

    func rebuildIfNeeded(_ config: PianoConfig) {
        if builtConfig == config { return }
        keymap = Self.keymap(for: config)
        notes.removeAll()
        sustainedNotes.removeAll()
        for (keycode, midi) in keymap {
            if config.modifierSustain && PianoModifierKeys.codes.contains(keycode) {
                if sustainedNotes[midi] == nil {
                    sustainedNotes[midi] = PianoSynth.render(midi: midi, sustain: min(2.0, config.sustain * 1.8))
                }
            } else if notes[midi] == nil {
                notes[midi] = PianoSynth.render(midi: midi, sustain: config.sustain)
            }
        }
        builtConfig = config
    }

    func buffer(for keycode: Int) -> AVAudioPCMBuffer? {
        guard let midi = keymap[keycode] else { return nil }
        if PianoModifierKeys.codes.contains(keycode), let sustained = sustainedNotes[midi] {
            return sustained
        }
        return notes[midi]
    }

    func previewBuffer(_ config: PianoConfig) -> AVAudioPCMBuffer {
        PianoSynth.render(midi: config.rootMidi, sustain: config.sustain)
    }

    // Map keycodes to MIDI notes by walking the visual rows. Each row gets
    // its own octave; position within the row picks a scale degree.
    static func keymap(for config: PianoConfig) -> [Int: Int] {
        let intervals = config.scale.intervals
        let root = config.rootMidi
        var map: [Int: Int] = [:]

        // KeyboardLayout.rows index: 0 F-row, 1 numbers, 2 qwerty, 3 home,
        // 4 bottom letters, 5 modifiers. Pitch rows from low to high:
        let pitchRows: [(rowIdx: Int, octaveOffset: Int)] = [
            (4, -12), (3, 0), (2, 12), (1, 24)
        ]

        for (rowIdx, octaveOffset) in pitchRows {
            let row = KeyboardLayout.rows[rowIdx]
            let pianoKeys = row.filter { isPianoKey($0) }
            for (i, kd) in pianoKeys.enumerated() {
                let octBump = (i / intervals.count) * 12
                let deg = i % intervals.count
                map[kd.keycode] = root + octaveOffset + octBump + intervals[deg]
            }
        }

        // Special anchor notes for the heavy keys so typing prose still rings.
        // Space = a low bass note, Enter = a high call, Backspace = soft mid.
        map[49] = root - 24     // Space
        map[36] = root + 19     // Enter (a 5th above an octave)
        map[51] = root - 5      // Backspace
        map[48] = root - 17     // Tab

        if config.modifierSustain {
            for (keycode, offset) in PianoModifierKeys.mappings {
                map[keycode] = root + offset
            }
        }

        return map
    }

    private static func isPianoKey(_ k: KeyDef) -> Bool {
        // Skip wide structural keys; their codes are handled as anchors.
        return k.width <= 1.0
    }
}
