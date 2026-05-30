// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #3 — "Feature Flex". 9:16, ~30 s loop. Everything Clonk does in
// three punchy acts: 10 switches quick-fire → live WPM tracker spiking →
// triggers/automation firing. "why is no one talking about this app" energy.
// NOT-@MainActor director (see ReelScene.swift header); shared ReelRecorder.

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

@Observable
final class FeatureFlexDirector: @unchecked Sendable, ReelDirecting {

    var act1Opacity = 1.0
    var act2Opacity = 0.0
    var act3Opacity = 0.0
    var outroOpacity = 0.0

    // Shared keyboard.
    var brightness = [Double](repeating: 0, count: KB.count)

    // Act 1 — switches.
    var a1Name = ""
    var a1Index = 0

    // Act 2 — WPM.
    var wpm = 0
    var bars = [Double](repeating: 0, count: 5)

    // Act 3 — automation.
    var ruleOpacity = 0.0
    var toastOpacity = 0.0
    var toastOffset: CGFloat = 40

    let cycleLength = 30.0

    private let a1Themes = ["clicky","tactile","linear","thock","typewriter","creamy","marble","hollow","paper","glass"]
    private let a1Names  = ["Clicky","Tactile","Linear","Thock","Typewriter","Creamy","Marble","Hollow","Cardboard","Glass"]
    private let keyPath  = [0,4,8,13,2,16,21,6,11,24,1,15,9,19,3,17,7,23,5,12]

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() { audio.prepareThemes(a1Themes) }

    func showIdleFrame() {
        reset(); act1Opacity = 1; a1Name = "Clicky"; a1Index = 1
    }

    func start() {
        ticker?.invalidate(); reset(); buildTimeline()
        cycleStart = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() { ticker?.invalidate(); ticker = nil; audio.setVolume(1.0); showIdleFrame() }

    private func reset() {
        act1Opacity = 1; act2Opacity = 0; act3Opacity = 0; outroOpacity = 0
        for i in brightness.indices { brightness[i] = 0 }
        a1Name = ""; a1Index = 0
        wpm = 0; for i in bars.indices { bars[i] = 0 }
        ruleOpacity = 0; toastOpacity = 0; toastOffset = 40
        events = []; elapsed = 0; audio.setVolume(1.0)
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        for i in brightness.indices { brightness[i] *= 0.80 }
        for i in bars.indices { bars[i] *= 0.86 }
        while !events.isEmpty, events[0].t <= elapsed { events.removeFirst().run() }
        if elapsed >= cycleLength { reset(); buildTimeline(); cycleStart = CACurrentMediaTime() }
    }

    private func at(_ t: Double, _ run: @escaping () -> Void) {
        let ev = (t: t, run: run)
        if let idx = events.firstIndex(where: { $0.t > t }) { events.insert(ev, at: idx) }
        else { events.append(ev) }
    }

    private func light(_ key: Int, _ v: Double = 1.0) {
        if key < brightness.count { brightness[key] = v }
    }

    private func buildTimeline() {
        var cursor = 0

        // ── Act 1: 10 switches ──────────────────────────────────────────
        for i in 0..<10 {
            let t = 0.4 + Double(i) * 0.85
            let theme = a1Themes[i]
            at(t) {
                self.a1Index = i + 1
                self.a1Name = self.a1Names[i]
                for _ in 0..<3 { self.light(self.keyPath[cursor % self.keyPath.count]); cursor += 1 }
                self.audio.play(themeId: theme, down: true, bigKey: false)
            }
            at(t + 0.15) { self.audio.play(themeId: theme, down: false, bigKey: false) }
        }
        at(9.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.act1Opacity = 0; self.act2Opacity = 1
            }
        }

        // ── Act 2: live WPM ─────────────────────────────────────────────
        var stroke = 0
        var t = 9.9
        while t < 17.9 {
            let captured = stroke
            at(t) {
                self.light(self.keyPath[captured % self.keyPath.count])
                self.bars[captured % self.bars.count] = Double.random(in: 0.55...1.0)
                self.wpm = min(151, 74 + captured * 2 + Int.random(in: -3...3))
                self.audio.play(themeId: captured % 2 == 0 ? "creamy" : "clicky", down: true, bigKey: false)
            }
            stroke += 1
            t += 0.2
        }
        at(17.9) { self.wpm = 148 }
        at(18.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.act2Opacity = 0; self.act3Opacity = 1
            }
        }

        // ── Act 3: triggers & automation ────────────────────────────────
        at(18.8) { withAnimation(.easeOut(duration: 0.5)) { self.ruleOpacity = 1 } }
        at(20.4) {
            self.toastOffset = 40; self.toastOpacity = 0
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.toastOpacity = 1; self.toastOffset = 0
            }
            self.audio.play(themeId: "thock", down: true, bigKey: true)
        }
        // Hands-free auto-typing under the rule.
        var t3 = 19.2
        var c3 = 0
        while t3 < 26.0 {
            let captured = c3
            at(t3) {
                self.light(self.keyPath[captured % self.keyPath.count], 0.9)
                self.audio.play(themeId: "thock", down: true, bigKey: false)
            }
            c3 += 1; t3 += 0.28
        }
        at(26.4) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.act3Opacity = 0; self.outroOpacity = 1
            }
        }
    }
}

// MARK: - Views

private struct ActHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .tracking(3).foregroundStyle(scAccent)
    }
}

private struct WPMBars: View {
    let bars: [Double]
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [scAccent, Color(red: 1, green: 0.45, blue: 0.05)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: CGFloat(14 + bars[i] * 92))
                    .shadow(color: scAccent.opacity(0.5 * bars[i]), radius: 8)
            }
        }
        .frame(height: 110, alignment: .bottom)
    }
}

struct FeatureFlexContent: View {
    let director: FeatureFlexDirector

    var body: some View {
        ZStack {
            ShowcaseBackground()
            act1.opacity(director.act1Opacity)
            act2.opacity(director.act2Opacity)
            act3.opacity(director.act3Opacity)
            outro.opacity(director.outroOpacity)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var act1: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)
            ActHeader(text: "10 SWITCHES")
            Spacer().frame(height: 30)
            Text(director.a1Name)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: scAccent.opacity(0.45), radius: 16)
                .frame(height: 50)
                .id(director.a1Name)
                .transition(.opacity)
            Text(String(format: "%02d / 10", director.a1Index))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(scAccent).tracking(2)
            Spacer().frame(height: 40)
            ShowcaseKeyboard(brightness: director.brightness)
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var act2: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 58)
            ActHeader(text: "LIVE WPM TRACKER")
            Spacer().frame(height: 24)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(director.wpm)")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: scAccent.opacity(0.5), radius: 18)
                    .contentTransition(.numericText())
                Text("WPM")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(scAccent)
            }
            .frame(height: 84)
            Spacer().frame(height: 18)
            WPMBars(bars: director.bars)
            Spacer().frame(height: 22)
            ShowcaseKeyboard(brightness: director.brightness)
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var act3: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 58)
            ActHeader(text: "TRIGGERS & AUTOMATION")
            Spacer().frame(height: 26)

            // The rule card.
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("WHEN").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    Text("typing > 120 WPM").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                Image(systemName: "arrow.down").font(.system(size: 13, weight: .bold)).foregroundStyle(scAccent)
                HStack(spacing: 8) {
                    Text("DO").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    Text("🔕  Focus Mode").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 1)))
            .opacity(director.ruleOpacity)

            Spacer().frame(height: 18)

            // Fired toast.
            HStack(spacing: 9) {
                Image(systemName: "bolt.fill").font(.system(size: 15, weight: .bold))
                Text("AUTOMATION FIRED").font(.system(size: 14, weight: .black, design: .rounded)).tracking(1)
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(scAccent).shadow(color: scAccent.opacity(0.6), radius: 12))
            .opacity(director.toastOpacity)
            .offset(y: director.toastOffset)

            Spacer().frame(height: 22)
            ShowcaseKeyboard(brightness: director.brightness)
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var outro: some View {
        VStack(spacing: 12) {
            Spacer()
            ShowcaseAppIcon(size: 110)
            Spacer().frame(height: 6)
            VStack(spacing: -2) {
                Text("MECHANICAL")
                Text("SOUND. ANY MAC.")
            }
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: scAccent.opacity(0.4), radius: 16)
            .multilineTextAlignment(.center)
            Text("10 switches · live WPM · triggers")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(scAccent)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

// MARK: - Holder + preview window

@Observable
final class FeatureFlexHolder: @unchecked Sendable {
    let director = FeatureFlexDirector()
    private var recorder: ReelRecorder?
    var isRecording = false
    var isPlaying   = false

    init() { director.showIdleFrame() }

    func togglePlay() {
        if isPlaying { director.stop(); isPlaying = false }
        else { director.start(); isPlaying = true }
    }

    func toggleRecord() {
        if isRecording {
            recorder?.stopSync(); recorder = nil; isRecording = false
            director.stop(); isPlaying = false
        } else {
            director.stop(); director.start(); isPlaying = true
            let d = director
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(FeatureFlexContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct FeatureFlexView: View {
    @State private var holder = FeatureFlexHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            FeatureFlexContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
