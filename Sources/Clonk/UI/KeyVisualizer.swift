import AppKit
import SwiftUI
import iUX

// Style for the key visualizer overlay.
//   .full     — full mini-keyboard, pressed keys highlighted.
//   .minimal  — only currently pressed (and recently released) keys,
//               fading out. No keyboard chrome.
// Lightweight record of a recent key event, used by the minimal-style
// overlay to draw and fade out keys after release.
struct KeyPressEvent: Identifiable {
    let id = UUID()
    let keycode: Int
    let label: String
    let pressedAt: Date
    var releasedAt: Date?
}

enum KeyVizStyle: String, Codable, CaseIterable, Identifiable {
    case full
    case minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: return "Full keyboard"
        case .minimal: return "Minimal"
        }
    }
}

// Floating mini-keyboard (or mini-piano in Piano Mode) that lights up
// keys as they're pressed. Reuses KeyboardLayout from AdvancedKeyboard.swift.
struct KeyVisualizerView: View {
    let model: AppModel

    var body: some View {
        Group {
            if model.pianoModeEnabled {
                PianoOverlay(model: model)
                    .glassPanel(padding: 12)
            } else if model.guitarModeEnabled {
                GuitarOverlay(model: model)
                    .glassPanel(padding: 12)
            } else {
                switch model.keyVizStyle {
                case .full:
                    keyboard
                        .glassPanel(padding: 12)
                case .minimal:
                    MinimalKeyOverlay(model: model)
                }
            }
        }
    }

    private var keyboard: some View {
        VStack(spacing: 3) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 3) {
                    ForEach(row) { key in
                        let pressed = model.pressedKeys.contains(key.keycode)
                        Text(key.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(pressed ? .black : .white)
                            .frame(
                                width: key.width * 22 + (key.width - 1) * 3,
                                height: 22
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(pressed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.08)))
                            )
                    }
                }
            }
        }
    }
}

// Minimal overlay: shows only the keys currently pressed and a brief
// fade-out trail for ones just released. The backdrop pill appears on
// hover only — it's the grab handle for dragging the window. The rest
// of the time the chips float bare, as a pure visualizer.
private struct MinimalKeyOverlay: View {
    let model: AppModel
    @State private var hovering = false

    // Lifetime of a released key on screen.
    static let fade: TimeInterval = 0.9
    // Spring used for layout shifts and chip enter/exit.
    private static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.7)
    // Cap visible chips so they never get squeezed past readability.
    private static let maxVisible = 8

    var body: some View {
        let allEvents = model.recentKeyEvents
        let events = Array(allEvents.suffix(Self.maxVisible))
        let idle = events.isEmpty
        // In minimal mode the pill is only a grab handle / affordance —
        // show it on hover only. When keys are flowing it stays hidden so
        // the chips read as a pure visualizer.
        let showBackdrop = hovering
        // Only run the timeline while there's a fading chip — pressed
        // chips are static, no per-frame redraw needed.
        let needsTimeline = events.contains { $0.releasedAt != nil }

        ZStack {
            // Invisible hit-testable layer so `.onHover` fires and the
            // window stays draggable from its background.
            Color.black.opacity(0.001)

            if showBackdrop {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(idle ? 0.32 : 0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(idle ? 0.22 : 0.10), lineWidth: 1)
                    )
                    .transition(.opacity)
            }

            if idle && hovering {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .transition(.opacity)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !needsTimeline)) { ctx in
                let now = ctx.date
                HStack(spacing: 6) {
                    ForEach(events) { e in
                        chip(for: e, now: now)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .animation(Self.spring, value: events.map(\.id))
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.2), value: showBackdrop)
    }

    private func chip(for e: KeyPressEvent, now: Date) -> some View {
        // Released chips fade alpha + drift up. Pressed chips render
        // statically — no per-frame math.
        let releaseT: Double = e.releasedAt.map { r in
            max(0, min(1, now.timeIntervalSince(r) / Self.fade))
        } ?? 0
        let alpha: Double = 1.0 - releaseT
        let drift: CGFloat = -8 * CGFloat(releaseT)

        return Text(e.label)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(.black.opacity(0.65))
            )
            .offset(y: drift)
            .opacity(alpha)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.6).combined(with: .opacity),
                removal: .opacity
            ))
    }
}

// Mini piano overlay. White and black keys laid out for the full MIDI
// range mapped by the active piano config; highlights any note whose
// keycode is currently pressed.
private struct PianoOverlay: View {
    let model: AppModel

    private static let whitePitches: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    var body: some View {
        let keymap = PianoBank.keymap(for: model.pianoConfig)
        let pressedMidi: Set<Int> = Set(model.pressedKeys.compactMap { keymap[$0] })
        let used = Set(keymap.values)
        let minM = (used.min() ?? 60) / 12 * 12
        let maxM = ((used.max() ?? 72) / 12 + 1) * 12 - 1
        let range = Array(minM...maxM)
        let whites = range.filter { Self.isWhite($0) }
        let blacks = range.filter { !Self.isWhite($0) }
        let whiteW: CGFloat = 12
        let whiteH: CGFloat = 56
        let blackW: CGFloat = 7
        let blackH: CGFloat = 34
        let gap: CGFloat = 1

        ZStack(alignment: .topLeading) {
            HStack(spacing: gap) {
                ForEach(whites, id: \.self) { m in
                    let on = pressedMidi.contains(m)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.white.opacity(0.92)))
                        .frame(width: whiteW, height: whiteH)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(.black.opacity(0.5), lineWidth: 0.5)
                        )
                }
            }
            ForEach(blacks, id: \.self) { m in
                if let x = Self.blackX(midi: m, whites: whites, whiteW: whiteW, gap: gap, blackW: blackW) {
                    let on = pressedMidi.contains(m)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.black))
                        .frame(width: blackW, height: blackH)
                        .offset(x: x)
                }
            }
        }
    }

    private static func isWhite(_ midi: Int) -> Bool {
        whitePitches.contains(((midi % 12) + 12) % 12)
    }

    // Center each black between its lower neighbour white and the next.
    private static func blackX(midi: Int, whites: [Int], whiteW: CGFloat, gap: CGFloat, blackW: CGFloat) -> CGFloat? {
        guard let belowIdx = whites.lastIndex(where: { $0 < midi }) else { return nil }
        let pitch = whiteW + gap
        let center = CGFloat(belowIdx + 1) * pitch - gap / 2
        return center - blackW / 2
    }
}

// Mini fretboard overlay. Six strings in standard tuning with frets and
// inlay markers; lights up the lowest playable fret position for any note
// whose keycode is currently pressed.
private struct GuitarOverlay: View {
    let model: AppModel

    // Open-string MIDI, low E → high E (standard tuning).
    private static let openStrings = [40, 45, 50, 55, 59, 64]
    private static let fretCount = 12
    private static let inlayFrets: Set<Int> = [3, 5, 7, 9, 12]

    private static let leftPad: CGFloat = 8     // frame → board inset (nut x)
    private static let topPad: CGFloat = 4      // frame → board inset (top/bottom)
    private static let vPad: CGFloat = 6        // board edge → outer string
    private static let sGap: CGFloat = 9
    private static let fGap: CGFloat = 15
    private static var boardW: CGFloat { fGap * CGFloat(fretCount) }
    // Span between the outer strings; the board adds vPad above and below.
    private static var stringSpan: CGFloat { sGap * CGFloat(openStrings.count - 1) }
    private static var boardH: CGFloat { stringSpan + vPad * 2 }

    var body: some View {
        let keymap = GuitarBank.keymap(for: model.guitarConfig)
        let pressedMidi = Set(model.pressedKeys.compactMap { keymap[$0] })
        let positions = pressedMidi.compactMap { Self.position(for: $0) }

        Canvas { ctx, _ in
            let board = CGRect(
                x: Self.leftPad, y: Self.topPad,
                width: Self.boardW, height: Self.boardH
            )
            ctx.fill(
                Path(roundedRect: board, cornerRadius: 3),
                with: .color(Color(red: 0.27, green: 0.18, blue: 0.11))
            )

            // Inlay markers between frets, centered on the board.
            for f in Self.inlayFrets where f <= Self.fretCount {
                let x = Self.fretX(f) - Self.fGap / 2
                let midY = Self.topPad + Self.boardH / 2
                if f == 12 {
                    Self.dot(ctx, x: x, y: midY - Self.sGap, r: 2, color: .white.opacity(0.25))
                    Self.dot(ctx, x: x, y: midY + Self.sGap, r: 2, color: .white.opacity(0.25))
                } else {
                    Self.dot(ctx, x: x, y: midY, r: 2, color: .white.opacity(0.25))
                }
            }

            // Frets span the full board height (nut at f == 0 is brighter/thicker).
            for f in 0...Self.fretCount {
                let x = Self.fretX(f)
                var p = Path()
                p.move(to: CGPoint(x: x, y: Self.topPad))
                p.addLine(to: CGPoint(x: x, y: Self.topPad + Self.boardH))
                ctx.stroke(p, with: .color(.white.opacity(f == 0 ? 0.85 : 0.22)),
                           lineWidth: f == 0 ? 2.5 : 1)
            }

            // Strings, low (thick) to high (thin).
            for s in 0..<Self.openStrings.count {
                let y = Self.stringY(s)
                var p = Path()
                p.move(to: CGPoint(x: Self.leftPad, y: y))
                p.addLine(to: CGPoint(x: Self.leftPad + Self.boardW, y: y))
                let thickness = 1.6 - CGFloat(s) * 0.18
                ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: thickness)
            }

            // Pressed notes. Everything stays within [leftPad, leftPad+boardW]
            // so a highlight never floats off the neck.
            for (s, fret) in positions {
                let y = Self.stringY(s)
                if fret == 0 {
                    // Open string: light the whole string and mark it at the nut.
                    var p = Path()
                    p.move(to: CGPoint(x: Self.leftPad, y: y))
                    p.addLine(to: CGPoint(x: Self.leftPad + Self.boardW, y: y))
                    ctx.stroke(p, with: .color(Color.accentColor), lineWidth: 2)
                    Self.dot(ctx, x: Self.fretX(0) + 4, y: y, r: 3, color: Color.accentColor)
                } else {
                    Self.dot(ctx, x: Self.fretX(fret) - Self.fGap / 2, y: y, r: 3.5,
                             color: Color.accentColor)
                }
            }
        }
        .frame(width: Self.leftPad + Self.boardW + 8, height: Self.topPad * 2 + Self.boardH)
    }

    private static func fretX(_ f: Int) -> CGFloat { leftPad + CGFloat(f) * fGap }

    // Low E (index 0) sits at the bottom, inset from the board edge by vPad.
    private static func stringY(_ s: Int) -> CGFloat {
        topPad + vPad + CGFloat(openStrings.count - 1 - s) * sGap
    }

    private static func dot(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                 with: .color(color))
    }

    // Pick the lowest fret position that can play this note, preferring
    // higher strings so notes cluster on the neck rather than spread out.
    private static func position(for midi: Int) -> (string: Int, fret: Int)? {
        var best: (string: Int, fret: Int)?
        for s in 0..<openStrings.count {
            let fret = midi - openStrings[s]
            guard fret >= 0, fret <= fretCount else { continue }
            if best == nil || fret < best!.fret {
                best = (s, fret)
            }
        }
        return best
    }
}
