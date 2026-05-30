// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Shared chrome + a brightness-driven keyboard, reused by the tier-list,
// feature-flex, and satisfying-loop showcases so they stay visually consistent.

#if CLONK_SHOWCASE

import AppKit
import SwiftUI

// Brand orange used across every showcase.
let scAccent = Color(red: 1.0, green: 0.55, blue: 0.10)

// MARK: - Background

struct ShowcaseBackground: View {
    var glow: Double = 0.12
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.013, blue: 0.018)
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.10).opacity(glow), .clear],
                center: .center, startRadius: 0, endRadius: 400
            )
            Canvas { ctx, size in
                let spacing: CGFloat = 34
                var p = Path()
                for x in stride(from: 0, through: size.width, by: spacing) {
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: spacing) {
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(p, with: .color(.white.opacity(0.018)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Footer + icon

struct ShowcaseFooter: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("CLONK")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.8))
            Circle().fill(scAccent).frame(width: 4, height: 4)
                .shadow(color: scAccent, radius: 4)
            Text("anti.ltd")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct ShowcaseAppIcon: View {
    let size: CGFloat
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
                .shadow(color: scAccent.opacity(0.25), radius: 16)
        }
    }
}

// MARK: - Preview controls

// The Play / Record bar shared by every showcase preview window.
struct ShowcaseControls: View {
    let isPlaying: Bool
    let isRecording: Bool
    let onPlay: () -> Void
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(isPlaying ? "⏸  Pause" : "▶  Play", action: onPlay)
                .buttonStyle(.bordered).tint(.white).controlSize(.regular)
                .disabled(isRecording)
            Button(isRecording ? "⏹  Stop Recording" : "⏺  Record 9:16", action: onRecord)
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .orange)
                .controlSize(.regular)
            Spacer()
            if isRecording {
                Text("Saving to Desktop…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.black)
    }
}

// MARK: - Keyboard

// Classic 26-key QWERTY layout, indices 0…25 row-major.
enum KB {
    static let rows: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],     // Q W E R T Y U I O P
        [10, 11, 12, 13, 14, 15, 16, 17, 18], // A S D F G H J K L
        [19, 20, 21, 22, 23, 24, 25],        // Z X C V B N M
    ]
    static let labels = [
        "Q","W","E","R","T","Y","U","I","O","P",
        "A","S","D","F","G","H","J","K","L",
        "Z","X","C","V","B","N","M",
    ]
    static let count = 26
    static let stagger: [CGFloat] = [0, 14, 30]

    // Column position (x order) of a key within the whole board, for wave math.
    static let column: [Double] = {
        var col = [Double](repeating: 0, count: count)
        for (r, row) in rows.enumerated() {
            for (c, idx) in row.enumerated() {
                col[idx] = Double(c) + Double(stagger[r]) / 31.0
            }
        }
        return col
    }()
    static let rowOf: [Double] = {
        var rr = [Double](repeating: 0, count: count)
        for (r, row) in rows.enumerated() { for idx in row { rr[idx] = Double(r) } }
        return rr
    }()
}

// Each key's glow is driven by `brightness[idx]` in 0…1.
struct ShowcaseKeyboard: View {
    let brightness: [Double]
    var keyW: CGFloat = 28
    var keyH: CGFloat = 30
    var gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    Spacer().frame(width: KB.stagger[r])
                    HStack(spacing: gap) {
                        ForEach(KB.rows[r], id: \.self) { idx in cap(idx) }
                    }
                }
            }
        }
    }

    private func b(_ idx: Int) -> Double {
        guard idx < brightness.count else { return 0 }
        return max(0, min(1, brightness[idx]))
    }

    private static let dimFill = LinearGradient(
        colors: [.white.opacity(0.10), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
    private static let litFill = LinearGradient(
        colors: [Color(red: 1, green: 0.66, blue: 0.20), Color(red: 0.95, green: 0.45, blue: 0.05)],
        startPoint: .top, endPoint: .bottom)

    private func cap(_ idx: Int) -> some View {
        let lit = b(idx)
        let labelColor: Color = lit > 0.5 ? Color.black.opacity(0.85) : Color.white.opacity(0.4)

        let base = RoundedRectangle(cornerRadius: 6).fill(Self.dimFill)
        let glow = RoundedRectangle(cornerRadius: 6).fill(Self.litFill).opacity(lit)
        let border = RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.white.opacity(0.06 + 0.5 * lit), lineWidth: 1)
        let label = Text(KB.labels[idx])
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(labelColor)

        return base
            .overlay(glow)
            .overlay(border)
            .overlay(label)
            .frame(width: keyW, height: keyH)
            .shadow(color: scAccent.opacity(0.8 * lit), radius: 14 * CGFloat(lit))
            .scaleEffect(CGFloat(1 + 0.05 * lit))
    }
}

#endif
