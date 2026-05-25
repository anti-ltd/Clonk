import AVFoundation

// Guitar Mode — every keystroke plucks a tuned guitar string instead of a
// click. Notes are synthesised with Karplus–Strong: a short noise burst
// excites a delay line whose length sets the pitch; a one-pole lowpass in
// the feedback loop sheds the highs first, giving the bright-then-mellow
// decay of a plucked string. Nothing on disk; banks rebuild whenever the
// scale or root note changes. Shares MusicalScale with Piano (see Piano.swift).

struct GuitarConfig: Codable, Equatable {
    // MIDI note for the home row's first letter (default = E3, low in the
    // guitar's range so the rows climb into a comfortable register).
    var rootMidi: Int = 52
    var scale: MusicalScale = .minorPentatonic
    // Ring-out length scale (0.4…2.0); shorter = palm-muted, longer = open.
    var sustain: Double = 1.0
    // When true, modifier keys (Shift/Cmd/Opt/Ctrl/Fn/CapsLock) play
    // long, low open-string drones — a held-chord effect.
    var modifierSustain: Bool = false
}

// macOS Carbon keycodes for modifier keys (Shift, Ctrl, Opt, Cmd, Fn, CapsLock).
enum GuitarModifierKeys {
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

// Procedural plucked-string rendering via Karplus–Strong. The delay line is
// seeded with a lightly low-passed noise burst (the pick), then iterated with
// a two-tap averaging filter and a per-sample loss factor that sets the
// overall ring time.
enum GuitarSynth {
    static let sampleRate: Double = Synth.sampleRate

    static func render(midi: Int, sustain: Double = 1.0) -> AVAudioPCMBuffer {
        let sr = sampleRate
        let clampedMidi = max(28, min(88, midi))
        let freq = 440.0 * pow(2.0, Double(clampedMidi - 69) / 12.0)

        // Lower notes ring longer. Sustain knob scales the whole thing.
        let baseDur = max(0.6, 2.2 - Double(clampedMidi - 40) * 0.02)
        let dur = baseDur * max(0.4, min(2.0, sustain))
        let count = Int(dur * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let out = buffer.floatChannelData![0]

        // Delay-line length sets the fundamental. Clamp so very high notes
        // still have a few taps to average.
        let n = max(2, Int((sr / freq).rounded()))
        var line = [Double](repeating: 0, count: n)

        // Pick excitation: white noise softened by a one-pole lowpass so the
        // attack reads warm rather than fizzy. Brighter pluck = steel-string.
        var rng = SystemRandomNumberGenerator()
        var lp = 0.0
        for i in 0..<n {
            let w = Double.random(in: -1...1, using: &rng)
            lp = lp * 0.5 + w * 0.5
            line[i] = lp
        }

        // Per-sample feedback tuned so the note loses ~60 dB across the buffer;
        // the loop's averaging filter shapes the timbre on top of that.
        let feedback = pow(0.001, 1.0 / Double(count))
        let attack = 0.002
        let release = 0.06

        var raw = [Double](repeating: 0, count: count)
        var peak = 0.0
        var ptr = 0
        for i in 0..<count {
            let cur = line[ptr]
            let nxt = line[(ptr + 1) % n]
            line[ptr] = (cur + nxt) * 0.5 * feedback
            var s = cur

            let t = Double(i) / sr
            if t < attack { s *= t / attack }
            let tailStart = Double(count) / sr - release
            if t > tailStart {
                s *= max(0, (Double(count) / sr - t) / release)
            }
            raw[i] = s
            peak = max(peak, abs(s))
            ptr = (ptr + 1) % n
        }
        let norm = peak > 1e-6 ? 0.82 / peak : 0
        for i in 0..<count {
            out[i] = Float(tanh(raw[i] * norm))
        }
        return buffer
    }
}

// Holds pre-rendered string buffers for whichever MIDI notes the current
// keymap uses. Rebuild on scale / root / sustain changes.
@MainActor
final class GuitarBank {
    private var notes: [Int: AVAudioPCMBuffer] = [:]
    private var sustainedNotes: [Int: AVAudioPCMBuffer] = [:]
    private(set) var keymap: [Int: Int] = [:]
    private var builtConfig: GuitarConfig?

    func rebuildIfNeeded(_ config: GuitarConfig) {
        if builtConfig == config { return }
        keymap = Self.keymap(for: config)
        notes.removeAll()
        sustainedNotes.removeAll()
        for (keycode, midi) in keymap {
            if config.modifierSustain && GuitarModifierKeys.codes.contains(keycode) {
                if sustainedNotes[midi] == nil {
                    sustainedNotes[midi] = GuitarSynth.render(midi: midi, sustain: min(2.0, config.sustain * 1.8))
                }
            } else if notes[midi] == nil {
                notes[midi] = GuitarSynth.render(midi: midi, sustain: config.sustain)
            }
        }
        builtConfig = config
    }

    func buffer(for keycode: Int) -> AVAudioPCMBuffer? {
        guard let midi = keymap[keycode] else { return nil }
        if GuitarModifierKeys.codes.contains(keycode), let sustained = sustainedNotes[midi] {
            return sustained
        }
        return notes[midi]
    }

    func previewBuffer(_ config: GuitarConfig) -> AVAudioPCMBuffer {
        GuitarSynth.render(midi: config.rootMidi, sustain: config.sustain)
    }

    // Map keycodes to MIDI notes by walking the visual rows. Each row gets
    // its own octave; position within the row picks a scale degree.
    static func keymap(for config: GuitarConfig) -> [Int: Int] {
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
            let guitarKeys = row.filter { isGuitarKey($0) }
            for (i, kd) in guitarKeys.enumerated() {
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
            for (keycode, offset) in GuitarModifierKeys.mappings {
                map[keycode] = root + offset
            }
        }

        return map
    }

    private static func isGuitarKey(_ k: KeyDef) -> Bool {
        // Skip wide structural keys; their codes are handled as anchors.
        return k.width <= 1.0
    }
}
