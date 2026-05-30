// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #1 — "Sound Check" ASMR reel. 9:16, ~30 s loop.
// Cycles through Clonk's switch voices one at a time; each lights a keycap
// cluster, pulses an audio waveform, and plays the *real* procedural switch
// sound. Calm, premium, headphones-on. Recorded via the shared ReelRecorder.
//
// Same macOS 26.5 concurrency rules as ReelScene.swift: the director is NOT
// @MainActor, its Timer callback calls tick() directly, and audio goes through
// the standalone ReelAudio engine — no Swift Concurrency on the hot path.
// See ReelScene.swift's header for the full rationale.

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

// MARK: - Switch line-up

private struct SoundSwitch {
    let themeId: String
    let name: String
    let descriptor: String
}

// MARK: - Director (NOT @MainActor — see file header)

@Observable
final class SoundCheckDirector: @unchecked Sendable, ReelDirecting {

    // Phase crossfade.
    var introOpacity   = 1.0
    var runningOpacity = 0.0
    var outroOpacity   = 0.0

    // Current switch labels.
    var switchIndex = 0
    var nameOpacity = 0.0
    var nameOffset: CGFloat = 18
    var descOpacity = 0.0

    // Keycap cluster — one key lit at a time as it "types".
    var litKey = -1

    // Waveform — amplitude spikes on each press, decays every tick.
    var waveAmp: CGFloat = 0
    var wavePhase: CGFloat = 0

    let cycleLength = 30.0

    fileprivate let switches: [SoundSwitch] = [
        .init(themeId: "thock",      name: "DEEP THOCK",         descriptor: "linear · deep · premium"),
        .init(themeId: "creamy",     name: "CREAMY LINEAR",      descriptor: "linear · smooth · lubed"),
        .init(themeId: "clicky",     name: "CLICKY BLUE",        descriptor: "clicky · bright · sharp"),
        .init(themeId: "tactile",    name: "TACTILE BROWN",      descriptor: "tactile · balanced · bump"),
        .init(themeId: "marble",     name: "MARBLE PLATE",       descriptor: "tactile · glassy · ping"),
        .init(themeId: "typewriter", name: "VINTAGE TYPEWRITER", descriptor: "clicky · loud · metallic"),
        .init(themeId: "hollow",     name: "HOLLOW CASE",        descriptor: "linear · boxy · low"),
    ]

    fileprivate var currentSwitch: SoundSwitch { switches[min(switchIndex, switches.count - 1)] }

    // Ripple path across the 14-key cluster — reads as playful typing, not a
    // left-to-right scan.
    private let keyPath = [5, 0, 6, 11, 2, 8, 13, 4, 9, 1, 7, 12, 3, 10]

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() {
        audio.prepareThemes(switches.map(\.themeId))
    }

    func showIdleFrame() {
        reset()
        introOpacity = 1
    }

    func start() {
        ticker?.invalidate()
        reset()
        buildTimeline()
        cycleStart = CACurrentMediaTime()
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
        introOpacity = 1; runningOpacity = 0; outroOpacity = 0
        switchIndex = 0; nameOpacity = 0; nameOffset = 18; descOpacity = 0
        litKey = -1; waveAmp = 0; wavePhase = 0
        events = []; elapsed = 0
        audio.setVolume(1.0)
    }

    private func tick() {
        // Wall-clock based, same as the reel — robust to Timer slip under the
        // 1080×1920 capture + H.264 encode load.
        elapsed = CACurrentMediaTime() - cycleStart
        wavePhase += 0.18
        waveAmp *= 0.90
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

    // MARK: Timeline

    private func buildTimeline() {
        let introEnd: Double = 2.5
        let segment:  Double = 3.4
        let pressOffsets: [Double] = [0.45, 0.95, 1.45, 1.95, 2.45, 2.95]

        // Intro → running.
        at(introEnd - 0.4) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.introOpacity = 0
                self.runningOpacity = 1
            }
        }

        var keyCursor = 0
        for (i, sw) in switches.enumerated() {
            let s = introEnd + Double(i) * segment

            // Reveal this switch's name + descriptor.
            at(s) {
                self.switchIndex = i
                self.nameOpacity = 0; self.nameOffset = 18; self.descOpacity = 0
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    self.nameOpacity = 1; self.nameOffset = 0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.12)) {
                    self.descOpacity = 1
                }
            }

            // Even, calm cadence — each press lights a keycap + pulses the wave.
            for (p, off) in pressOffsets.enumerated() {
                let big = (p % 3 == 2)
                let key = keyPath[keyCursor % keyPath.count]; keyCursor += 1
                at(s + off) {
                    self.litKey = key
                    self.waveAmp = 1.0
                    self.audio.play(themeId: sw.themeId, down: true, bigKey: big)
                }
                at(s + off + 0.16) {
                    self.audio.play(themeId: sw.themeId, down: false, bigKey: big)
                }
                at(s + off + 0.24) {
                    withAnimation(.easeOut(duration: 0.18)) { self.litKey = -1 }
                }
            }

            // Fade the labels out just before the next switch (all but last).
            if i < switches.count - 1 {
                at(s + segment - 0.35) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.nameOpacity = 0; self.descOpacity = 0
                    }
                }
            }
        }

        // Running → outro.
        let outroStart = introEnd + Double(switches.count) * segment
        at(outroStart - 0.3) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.runningOpacity = 0
                self.outroOpacity = 1
            }
        }
    }
}

// MARK: - Background

private struct SCBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.013, blue: 0.018)
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.10).opacity(0.12), .clear],
                center: .center, startRadius: 0, endRadius: 380
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

// MARK: - Waveform

private struct WaveformView: View {
    let amp: CGFloat
    let phase: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2
            let w = size.width
            let samples = 130

            // Center baseline.
            var base = Path()
            base.move(to: CGPoint(x: 0, y: midY))
            base.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(base, with: .color(.white.opacity(0.07)), lineWidth: 1)

            // The wave: two beating sines under a center-weighted envelope so a
            // press reads as a burst that blooms from the middle and settles.
            var path = Path()
            for i in 0...samples {
                let u = CGFloat(i) / CGFloat(samples)         // 0…1
                let x = w * u
                let env = sin(u * .pi)                         // 0 at edges, 1 center
                let wob = sin(u * 23 + phase) * 0.6
                        + sin(u * 41 - phase * 1.3) * 0.4
                let y = midY + wob * env * amp * (size.height * 0.46)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.addFilter(.shadow(color: .orange.opacity(0.55), radius: 9))
            ctx.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.orange.opacity(0.85),
                        Color(red: 1.0, green: 0.62, blue: 0.22),
                        Color.orange.opacity(0.85),
                    ]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
                lineWidth: 2.5
            )
        }
    }
}

// MARK: - Keycap cluster

private struct KeycapCluster: View {
    let litKey: Int

    private static let rows: [[Int]] = [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11, 12, 13]]
    private static let labels = ["Q","W","E","R","T","A","S","D","F","G","Z","X","C","V"]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(Self.rows[r], id: \.self) { k in
                        cap(Self.labels[k], on: k == litKey)
                    }
                }
            }
        }
    }

    private func cap(_ label: String, on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(on
                  ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 1, green: 0.66, blue: 0.20),
                                 Color(red: 0.95, green: 0.45, blue: 0.05)],
                        startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(LinearGradient(
                        colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom)))
            .frame(width: 40, height: 44)
            .overlay(
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(on ? Color.black.opacity(0.85) : .white.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(on ? 0.6 : 0.08), lineWidth: 1)
            )
            .shadow(color: on ? Color.orange.opacity(0.8) : .black.opacity(0.4),
                    radius: on ? 16 : 3, y: on ? 0 : 2)
            .scaleEffect(on ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

// MARK: - Small parts

private struct SoundOnPill: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .bold))
            Text("SOUND ON")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2.5)
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.black.opacity(0.6))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(pulse ? 0.7 : 0.3), lineWidth: 1))
                .shadow(color: Color.orange.opacity(pulse ? 0.4 : 0.15), radius: 9)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct ProgressDots: View {
    let count: Int
    let active: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == active ? Color.orange : Color.white.opacity(0.20))
                    .frame(width: i == active ? 8 : 6, height: i == active ? 8 : 6)
                    .shadow(color: i == active ? Color.orange.opacity(0.8) : .clear, radius: 5)
                    .animation(.easeOut(duration: 0.3), value: active)
            }
        }
    }
}

private struct SCFooter: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("CLONK")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.8))
            Circle().fill(Color.orange).frame(width: 4, height: 4)
                .shadow(color: Color.orange, radius: 4)
            Text("anti.ltd")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct SCAppIcon: View {
    let size: CGFloat
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
                .shadow(color: Color.orange.opacity(0.25), radius: 16)
        }
    }
}

// MARK: - Scene content

struct SoundCheckContent: View {
    let director: SoundCheckDirector

    var body: some View {
        ZStack {
            SCBackground()
            runningView.opacity(director.runningOpacity)
            introView.opacity(director.introOpacity)
            outroView.opacity(director.outroOpacity)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var runningView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)
            SoundOnPill()
            Spacer().frame(height: 22)
            ProgressDots(count: director.switches.count, active: director.switchIndex)
            Spacer().frame(height: 30)

            VStack(spacing: 8) {
                Text(director.currentSwitch.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(
                        colors: [.white, Color(red: 1.0, green: 0.90, blue: 0.78)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.orange.opacity(0.40), radius: 14)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                    .opacity(director.nameOpacity)
                    .offset(y: director.nameOffset)
                Text(director.currentSwitch.descriptor)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(1)
                    .opacity(director.descOpacity)
            }
            .frame(height: 80)

            Spacer().frame(height: 16)
            WaveformView(amp: director.waveAmp, phase: director.wavePhase)
                .frame(height: 128)
                .padding(.horizontal, 26)
            Spacer().frame(height: 26)
            KeycapCluster(litKey: director.litKey)

            Spacer(minLength: 10)
            SCFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var introView: some View {
        VStack(spacing: 16) {
            Spacer()
            SCAppIcon(size: 104)
            Text("SOUND CHECK")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(
                    colors: [.white, Color(red: 1.0, green: 0.90, blue: 0.78)],
                    startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.orange.opacity(0.4), radius: 16)
                .tracking(1)
            Text("every Clonk switch, one by one")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer().frame(height: 6)
            Label("headphones recommended", systemImage: "headphones")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.6))
                    .overlay(Capsule().strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)))
            Spacer()
            SCFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var outroView: some View {
        VStack(spacing: 12) {
            Spacer()
            SCAppIcon(size: 110)
            Spacer().frame(height: 6)
            VStack(spacing: -2) {
                Text("10 SOUNDS.")
                Text("ONE APP.")
            }
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundStyle(LinearGradient(
                colors: [.white, Color(red: 1.0, green: 0.90, blue: 0.78)],
                startPoint: .top, endPoint: .bottom))
            .shadow(color: Color.orange.opacity(0.4), radius: 16)
            .multilineTextAlignment(.center)
            Text("every switch · any mac")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.orange)
                .tracking(0.5)
            Spacer()
            SCFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

// MARK: - Holder + preview window

@Observable
final class SoundCheckHolder: @unchecked Sendable {
    let director = SoundCheckDirector()
    private var recorder: ReelRecorder?
    var isRecording = false
    var isPlaying   = false

    init() {
        director.showIdleFrame()
    }

    func togglePlay() {
        if isPlaying {
            director.stop(); isPlaying = false
        } else {
            director.start(); isPlaying = true
        }
    }

    func toggleRecord() {
        if isRecording {
            recorder?.stopSync(); recorder = nil
            isRecording = false
            director.stop(); isPlaying = false
        } else {
            director.stop(); director.start(); isPlaying = true
            let d = director
            let rec = ReelRecorder(director: d,
                                   makeRootView: { AnyView(SoundCheckContent(director: d)) })
            recorder = rec
            isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct SoundCheckView: View {
    @State private var holder = SoundCheckHolder()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SoundCheckContent(director: holder.director)
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
