// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// "can klack do this?" — self-recording 9:16 reply reel, 12 s loop.
// A crying little guy while Piano Mode plays a sad lament, then the
// KLACKREFUGEE stamp slams down.
// Design space: 360×640. Capture window: 1080×1920 (3×).
// Output: ~/Desktop/Clonk-Reel-<timestamp>.mp4
//
// IMPORTANT concurrency note for macOS 26.5:
//   `swift_task_isCurrentExecutorWithFlagsImpl` crashes when called from
//   non-async contexts (Timer callbacks, NSTimer fires). That rules out
//   `MainActor.assumeIsolated` AND `Task { @MainActor in ... }` creation
//   from Timer callbacks. This file therefore avoids Swift Concurrency on
//   the hot path: the director is NOT @MainActor, its Timer callback calls
//   tick() directly, and audio is handled by a standalone `ReelAudio` class
//   that doesn't require @MainActor isolation.

#if CLONK_SHOWCASE

import AppKit
import AVFoundation
import SwiftUI

// MARK: - Standalone audio engine (non-isolated, thread-safe)
//
// Built specifically so the director's Timer callback can play sounds
// without bridging to the app's @MainActor `SoundEngine`. Pre-renders a
// `ThemeBank` per theme on init, then plays buffers via a round-robin pool
// of AVAudioPlayerNodes under a lock.

final class ReelAudio: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let lock = NSLock()
    private var banks: [String: ThemeBank] = [:]
    private let voiceCount = 8

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        // Pre-render the three banks we use. ThemeBank/Synth are plain
        // structs/static functions — no actor isolation.
        for id in ["clicky", "thock", "creamy"] {
            banks[id] = ThemeBank.build(from: Theme.builtIn(id: id))
        }
        try? engine.start()
    }

    func play(themeId: String, down: Bool, bigKey: Bool) {
        guard let bank = banks[themeId] else { return }
        if !down && !bank.hasRelease { return }
        let buffer = down ? bank.pressBuffer(big: bigKey) : bank.releaseBuffer(big: bigKey)

        lock.lock()
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % voiceCount
        lock.unlock()

        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func setVolume(_ v: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, v))
    }

    // MARK: Piano Mode — render Clonk's real procedural notes once, then
    // schedule them on the same round-robin voice pool as the click banks.
    private var pianoNotes: [Int: AVAudioPCMBuffer] = [:]

    func preparePiano(_ midis: [Int]) {
        for m in Set(midis) where pianoNotes[m] == nil {
            pianoNotes[m] = PianoSynth.render(midi: m, sustain: 1.5)
        }
    }

    func playPiano(midi: Int) {
        guard let buffer = pianoNotes[midi] else { return }
        lock.lock()
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % voiceCount
        lock.unlock()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

// MARK: - Background

private struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 32
            var p = Path()
            for x in stride(from: 0, through: size.width, by: spacing) {
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(p, with: .color(Color.white.opacity(0.022)), lineWidth: 1)
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.clear, .black.opacity(0.85)]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: min(size.width, size.height) * 0.30,
                    endRadius: max(size.width, size.height) * 0.72
                )
            )
        }
    }
}

private struct AmbientHalo: View {
    let opacity: Double
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.55, blue: 0.15).opacity(0.32),
                    Color(red: 1.0, green: 0.45, blue: 0.05).opacity(0.10),
                    .clear,
                ],
                center: .center, startRadius: 0, endRadius: 300
            ))
            .frame(width: 620, height: 620)
            .scaleEffect(breathing ? 1.04 : 0.96)
            .blur(radius: 28)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

private struct AppIconImage: View {
    let size: CGFloat
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 6)
                .shadow(color: Color.orange.opacity(0.25), radius: 18)
        }
    }
}

// MARK: - Typewriter wordmark

private struct ReelWord: View {
    let text: String
    private struct Letter: Identifiable { let id: Int; let char: Character }
    private var letters: [Letter] {
        Array(text.enumerated()).map { Letter(id: $0.offset, char: $0.element) }
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(letters) { l in
                Text(String(l.char))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.6).combined(with: .opacity),
                        removal:   .scale(scale: 0.4).combined(with: .opacity)
                    ))
            }
        }
        .font(.system(size: 60, weight: .bold, design: .monospaced))
        .foregroundStyle(LinearGradient(
            colors: [.white, Color(red: 1.0, green: 0.92, blue: 0.82)],
            startPoint: .top, endPoint: .bottom
        ))
        .shadow(color: Color.orange.opacity(0.40), radius: 20)
        .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
        .fixedSize()
    }
}

// MARK: - Sparkle Ring (bumper)

private struct SparkleRing: View {
    private static let count = 14
    @State private var rotation: Double = 0
    @State private var pulsing = false

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { i in
                let angle = Double(i) / Double(Self.count) * 360
                Circle()
                    .fill(Color.orange)
                    .frame(width: 4, height: 4)
                    .shadow(color: Color.orange.opacity(pulsing ? 0.75 : 0.35), radius: 6)
                    .opacity(pulsing ? 0.9 : 0.5)
                    .offset(x: 95, y: 0)
                    .rotationEffect(.degrees(angle))
            }
        }
        .rotationEffect(.degrees(rotation))
        .frame(width: 220, height: 220)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Keyboard Visualizer

private struct ReelKeyboard: View {
    var pressedKeys: Set<Int>
    var active: Bool

    private static let rows: [[Int]] = [
        [12, 13, 14, 15, 17, 16, 32, 34, 31, 35],
        [0,  1,  2,  3,  5,  4,  38, 40, 37],
        [6,  7,  8,  9,  11, 45, 46]
    ]
    private static let labels: [[String]] = [
        ["Q","W","E","R","T","Y","U","I","O","P"],
        ["A","S","D","F","G","H","J","K","L"],
        ["Z","X","C","V","B","N","M"]
    ]
    private static let stagger: [CGFloat] = [0, 13, 26]

    private let kW: CGFloat = 26
    private let kH: CGFloat = 30
    private let gap: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    Spacer().frame(width: Self.stagger[row])
                    HStack(spacing: gap) {
                        ForEach(0..<Self.rows[row].count, id: \.self) { col in
                            let kc = Self.rows[row][col]
                            let on = pressedKeys.contains(kc)
                            keyCap(label: Self.labels[row][col], on: on)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(active ? 0.04 : 0.02),
                        Color.black.opacity(0.55),
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(active ? 0.12 : 0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
        )
    }

    @ViewBuilder
    private func keyCap(label: String, on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                on
                ? AnyShapeStyle(LinearGradient(
                    colors: [Color(red: 1, green: 0.65, blue: 0.20),
                             Color(red: 0.95, green: 0.45, blue: 0.05)],
                    startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom))
            )
            .frame(width: kW, height: kH)
            .overlay(
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? Color.black.opacity(0.85) : .white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(on ? 0.55 : 0.10), lineWidth: 0.5)
            )
            .shadow(
                color: on ? Color.orange.opacity(0.75) : Color.black.opacity(0.4),
                radius: on ? 12 : 2, y: on ? 0 : 1
            )
            .animation(.easeOut(duration: 0.07), value: on)
    }
}

// MARK: - Theme Badge

private struct ThemeBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(Color.orange)
            .tracking(3.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.72))
                    .overlay(Capsule()
                        .strokeBorder(Color.orange.opacity(0.55), lineWidth: 1))
                    .shadow(color: Color.orange.opacity(0.35), radius: 10)
            )
    }
}

// MARK: - Typing Display

private struct TypingLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 1) {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
            Rectangle()
                .fill(Color.orange)
                .frame(width: 2, height: 16)
                .shadow(color: Color.orange.opacity(0.7), radius: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 240, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Feature List

private struct ReelFeatureList: View {
    let revealCount: Int
    private static let items: [(String, String)] = [
        ("speaker.wave.3.fill", "10 authentic switches"),
        ("chart.bar.fill",      "Live WPM tracker"),
        ("bolt.fill",           "Trigger automation"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.items.enumerated()), id: \.offset) { idx, item in
                let shown = idx < revealCount
                HStack(spacing: 12) {
                    Image(systemName: item.0)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .shadow(color: .orange.opacity(shown ? 0.55 : 0), radius: 7)
                        .frame(width: 24)
                    Text(item.1)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -16)
                .scaleEffect(shown ? 1.0 : 0.88, anchor: .leading)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: revealCount)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1))
        )
    }
}

// MARK: - Footer

private struct Footer: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.orange).frame(width: 5, height: 5)
                .shadow(color: Color.orange, radius: 4)
            Text("BY  ANTI.LTD")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(3.5)
        }
    }
}

// MARK: - Director (NOT @MainActor — see file header)

@Observable
final class ReelDirector: @unchecked Sendable {

    var titleOpacity   = 0.0
    var guyOpacity     = 0.0
    var haloOpacity    = 0.7
    var contentOpacity = 1.0

    var keyboardOpacity = 0.35
    var keyboardActive  = false
    var pressedKeys: Set<Int> = []

    var stampOpacity = 0.0
    var stampScale   = 2.6

    let cycleLength = 12.0

    // Chopin's Funeral March (public domain) — the universal "someone died"
    // theme, played through Piano Mode. (time, midi, keycode-to-flash)
    static let melody: [(Double, Int, Int)] = [
        (1.0, 70, 12), (1.8, 70, 13), (2.4, 70, 14), (2.7, 70, 15),
        (3.3, 73, 17), (4.1, 72, 16), (4.7, 72, 32), (5.0, 70, 34),
        (5.6, 70, 31), (6.4, 69, 35), (7.0, 69, 0),  (7.3, 70, 1),
    ]
    // Low bass pedal on the downbeats.
    static let bass: [(Double, Int)] = [(1.0, 46), (3.3, 46), (5.6, 46), (7.3, 46)]

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0   // wall-clock anchor for this cycle
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() {
        audio.preparePiano(Self.melody.map(\.1) + Self.bass.map(\.1))
    }

    func showIdleFrame() {
        reset()
        titleOpacity    = 1
        guyOpacity      = 1
        keyboardOpacity = 1
        stampOpacity    = 1
        stampScale      = 1.0
    }

    func start() {
        ticker?.invalidate()
        reset()
        buildTimeline()
        cycleStart = CACurrentMediaTime()
        // Timer in .common runloop modes so it fires during mouse tracking
        // too. Callback calls tick() DIRECTLY — no Task, no MainActor hop.
        // The director is non-isolated and tick() only touches state that's
        // accessed from the main thread by convention (Timer-on-main +
        // SwiftUI render-on-main).
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        audio.setVolume(1.0)
        showIdleFrame()
    }

    private func reset() {
        titleOpacity = 0; guyOpacity = 0; haloOpacity = 0.7
        keyboardOpacity = 0.35; keyboardActive = false; pressedKeys = []
        stampOpacity = 0; stampScale = 2.6
        contentOpacity = 1
        events = []; elapsed = 0
        audio.setVolume(1.0)
    }

    private func tick() {
        // Wall-clock based — robust to Timer slip under recording load.
        // If we incremented by 1/60 per tick, a Timer that can only fire
        // 30×/sec (because the main RunLoop is busy compositing the
        // 1080×1920 capture window + encoding H.264) would make the entire
        // timeline play at half speed, and the wall-clock autoStopTask in
        // ReelRecorder would chop the recording in half.
        elapsed = CACurrentMediaTime() - cycleStart
        while !events.isEmpty, events[0].t <= elapsed {
            events.removeFirst().run()
        }
        if elapsed >= cycleLength {
            reset(); buildTimeline()
            cycleStart = CACurrentMediaTime()
        }
    }

    private func at(_ t: Double, _ run: @escaping () -> Void) {
        let ev = (t: t, run: run)
        if let idx = events.firstIndex(where: { $0.t > t }) {
            events.insert(ev, at: idx)
        } else {
            events.append(ev)
        }
    }

    // MARK: - Timeline

    private func buildTimeline() {
        at(0.2) { withAnimation(.easeOut(duration: 0.5)) { self.titleOpacity = 1 } }
        at(0.6) {
            self.keyboardActive = true
            withAnimation(.easeOut(duration: 0.5)) {
                self.guyOpacity = 1
                self.keyboardOpacity = 1
            }
        }

        // The lament: one piano note per beat, each lighting up a key.
        for (t, midi, kc) in Self.melody {
            at(t) {
                self.pressedKeys.insert(kc)
                self.audio.playPiano(midi: midi)
            }
            at(t + 0.30) { self.pressedKeys.remove(kc) }
        }
        for (t, midi) in Self.bass {
            at(t) { self.audio.playPiano(midi: midi) }
        }

        // KLACKREFUGEE stamp slams down over the crying guy.
        at(8.7) {
            self.stampOpacity = 0
            self.stampScale = 2.6
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                self.stampOpacity = 1
                self.stampScale = 1.0
            }
            self.audio.playPiano(midi: 45)
        }

        // Audio fade just before the cycle resets at 12.0 s.
        let fadeSteps = 8
        for i in 0..<fadeSteps {
            let t   = 10.8 + Double(i) * (0.7 / Double(fadeSteps))
            let vol = 1.0 - Double(i + 1) / Double(fadeSteps)
            at(t) { self.audio.setVolume(Float(vol)) }
        }
    }
}

// MARK: - Crying refugee

private struct Tear: View {
    let x: CGFloat
    let delay: Double
    @State private var fall = false
    var body: some View {
        Text("💧")
            .font(.system(size: 22))
            .offset(x: x, y: fall ? 96 : 6)
            .opacity(fall ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeIn(duration: 1.5)
                    .repeatForever(autoreverses: false).delay(delay)) {
                    fall = true
                }
            }
    }
}

private struct CryingGuy: View {
    @State private var bob = false
    var body: some View {
        ZStack {
            Text("😭")
                .font(.system(size: 130))
                .scaleEffect(bob ? 1.0 : 0.93)
                .rotationEffect(.degrees(bob ? -3 : 3))
                .shadow(color: Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.4), radius: 22)
            Tear(x: -30, delay: 0.0)
            Tear(x:  32, delay: 0.7)
            Tear(x:  -8, delay: 1.4)
        }
        .frame(width: 200, height: 190)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
    }
}

private struct KlackStamp: View {
    private let ink = Color(red: 1.0, green: 0.26, blue: 0.22)
    var body: some View {
        VStack(spacing: -4) {
            Text("KLACK")
            Text("REFUGEE")
        }
        .font(.system(size: 40, weight: .black, design: .rounded))
        .tracking(2)
        .foregroundStyle(ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ink, lineWidth: 4)
        )
        .rotationEffect(.degrees(-11))
        .shadow(color: .black.opacity(0.55), radius: 8)
    }
}

// MARK: - Scene content

struct ReelSceneContent: View {
    let director: ReelDirector

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.013, blue: 0.018)
            GridBackground()
            AmbientHalo(opacity: director.haloOpacity)

            VStack(spacing: 0) {
                Spacer().frame(height: 76)

                Text("can klack do this?")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [.white, Color(red: 1.0, green: 0.92, blue: 0.82)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.orange.opacity(0.40), radius: 16)
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 2)
                    .opacity(director.titleOpacity)
                    .frame(height: 40)

                Spacer().frame(height: 28)

                ZStack {
                    CryingGuy()
                        .opacity(director.guyOpacity)
                    KlackStamp()
                        .scaleEffect(director.stampScale)
                        .opacity(director.stampOpacity)
                }
                .frame(height: 200)

                Text("use code KLACKREFUGEE for a discount")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .opacity(director.stampOpacity)
                    .frame(height: 20)

                Spacer().frame(height: 18)

                ReelKeyboard(pressedKeys: director.pressedKeys, active: director.keyboardActive)
                    .opacity(director.keyboardOpacity)

                Spacer(minLength: 16)

                Footer()
                    .padding(.bottom, 22)
            }
            .frame(width: 360, height: 640)
            .opacity(director.contentOpacity)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}

struct ReelSceneViewBound: View {
    let director: ReelDirector
    var body: some View {
        ReelSceneContent(director: director)
    }
}

// MARK: - Holder

@Observable
final class ReelHolder: @unchecked Sendable {
    let director = ReelDirector()
    private var recorder: ReelRecorder?
    var isRecording = false
    var isPlaying   = false

    init() {
        director.showIdleFrame()
    }

    func togglePlay() {
        if isPlaying {
            director.stop()
            isPlaying = false
        } else {
            director.start()
            isPlaying = true
        }
    }

    func toggleRecord() {
        if isRecording {
            recorder?.stopSync()
            recorder = nil
            isRecording = false
            director.stop()
            isPlaying = false
        } else {
            director.stop()
            director.start()
            isPlaying = true
            let rec = ReelRecorder(director: director)
            recorder = rec
            isRecording = true
            Task { await rec.start() }
        }
    }
}

// MARK: - Preview window

public struct ReelSceneView: View {
    @State private var holder = ReelHolder()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ReelSceneContent(director: holder.director)
                .frame(width: 360, height: 640)

            HStack(spacing: 10) {
                Button(holder.isPlaying ? "⏸  Pause" : "▶  Play") {
                    holder.togglePlay()
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.regular)
                .disabled(holder.isRecording)

                Button(holder.isRecording ? "⏹  Stop Recording" : "⏺  Record 9:16") {
                    holder.toggleRecord()
                }
                .buttonStyle(.borderedProminent)
                .tint(holder.isRecording ? .red : .orange)
                .controlSize(.regular)

                Spacer()

                if holder.isRecording {
                    Text("Saving to Desktop…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black)
        }
        .frame(width: 360)
    }
}

#endif
