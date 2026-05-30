// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Shared instrument visuals for the Piano / Guitar / Duet showcases:
// a drawn piano keyboard, a Synthesia-style falling-note roll, and a set of
// vibrating guitar strings. Geometry is shared so the roll's notes line up
// with the keys they fall onto.

#if CLONK_SHOWCASE

import SwiftUI

// A scheduled note: absolute time within the loop + MIDI pitch.
struct ShowNote {
    let t: Double
    let midi: Int
}

// Tile a MIDI pattern into absolute-timed notes filling [start, end).
func tileMelody(_ pattern: [Int], from start: Double, to end: Double, step: Double) -> [ShowNote] {
    var notes: [ShowNote] = []
    var t = start
    var i = 0
    while t < end {
        notes.append(ShowNote(t: t, midi: pattern[i % pattern.count]))
        t += step; i += 1
    }
    return notes
}

// MARK: - Piano geometry

struct PianoGeometry {
    let width: CGFloat
    let low: Int
    let high: Int

    static let blackPCs: Set<Int> = [1, 3, 6, 8, 10]
    func isBlack(_ m: Int) -> Bool { Self.blackPCs.contains(((m % 12) + 12) % 12) }

    var whiteMidis: [Int] { (low...high).filter { !isBlack($0) } }
    var whiteW: CGFloat { width / CGFloat(max(1, whiteMidis.count)) }

    func xCenter(_ m: Int) -> CGFloat {
        if !isBlack(m) {
            let i = whiteMidis.firstIndex(of: m) ?? 0
            return (CGFloat(i) + 0.5) * whiteW
        } else {
            let i = whiteMidis.firstIndex(of: m - 1) ?? 0   // black sits above the white below it
            return CGFloat(i + 1) * whiteW
        }
    }
}

// MARK: - Piano keyboard

struct PianoKeyboard: View {
    let lit: Set<Int>
    var low = 60
    var high = 84

    var body: some View {
        Canvas { ctx, size in
            let geo = PianoGeometry(width: size.width, low: low, high: high)
            let ww = geo.whiteW

            // White keys.
            for (i, m) in geo.whiteMidis.enumerated() {
                let rect = CGRect(x: CGFloat(i) * ww + 1, y: 0, width: ww - 2, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                let on = lit.contains(m)
                ctx.fill(path, with: .color(on ? scAccent : Color(white: 0.93)))
                ctx.stroke(path, with: .color(.black.opacity(0.30)), lineWidth: 1)
            }

            // Black keys on top.
            let bh = size.height * 0.62
            let bw = ww * 0.6
            for m in low...high where geo.isBlack(m) {
                let xc = geo.xCenter(m)
                let rect = CGRect(x: xc - bw / 2, y: 0, width: bw, height: bh)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                let on = lit.contains(m)
                ctx.fill(path, with: .color(on ? scAccent : Color(white: 0.08)))
                if on {
                    ctx.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Falling-note roll (Synthesia style)

struct PianoRoll: View {
    let notes: [ShowNote]
    let clock: Double
    var lookahead: Double = 2.4
    var low = 60
    var high = 84

    var body: some View {
        Canvas { ctx, size in
            let geo = PianoGeometry(width: size.width, low: low, high: high)
            let pxPerSec = size.height / lookahead
            let barH = max(10, 0.24 * pxPerSec)

            for note in notes {
                let dt = note.t - clock
                if dt < -0.15 || dt > lookahead { continue }
                let progress = dt / lookahead                 // 0 = at keys, 1 = far
                let yCenter = size.height * (1 - progress)
                let xc = geo.xCenter(note.midi)
                let w = geo.isBlack(note.midi) ? geo.whiteW * 0.5 : geo.whiteW * 0.66
                let rect = CGRect(x: xc - w / 2, y: yCenter - barH / 2, width: w, height: barH)
                let path = Path(roundedRect: rect, cornerRadius: 3)
                let op = 1 - progress * 0.6
                ctx.fill(path, with: .color(scAccent.opacity(op)))
                ctx.stroke(path, with: .color(.white.opacity(0.25 * op)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Guitar strings

struct GuitarStrings: View {
    let amps: [Double]      // one per string, 0…1
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let n = max(1, amps.count)
            for s in 0..<n {
                let y = size.height * (Double(s) + 0.5) / Double(n)
                let amp = amps[s]
                let A = amp * (size.height / Double(n)) * 0.42
                let freq = 7.0 + Double(s) * 1.6
                var path = Path()
                let steps = 120
                for i in 0...steps {
                    let u = Double(i) / Double(steps)
                    let x = size.width * u
                    let env = sin(u * .pi)
                    let yy = y + sin(u * freq * .pi + phase) * env * A
                    let pt = CGPoint(x: x, y: yy)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                let bright = 0.22 + amp * 0.78
                let lw = 1.3 + amp * 1.8
                // Fake a glow by laying a soft wide stroke under a bright thin one.
                if amp > 0.05 {
                    ctx.stroke(path, with: .color(scAccent.opacity(0.25 * amp)), lineWidth: lw + 6)
                }
                ctx.stroke(path, with: .color(scAccent.opacity(bright)), lineWidth: lw)
            }
        }
    }
}

#endif
