// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #6 — "Guitar Mode". 9:16, ~30 s loop. Clonk fingerpicks an
// Am–F–C–G arpeggio on Guitar Mode: each note plucks a vibrating string and
// lights the key that played it, voiced by the real GuitarSynth (Karplus–
// Strong). NOT-@MainActor director (see ReelScene.swift header).

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

@Observable
final class GuitarModeDirector: @unchecked Sendable, ReelDirecting {

    var introOpacity   = 1.0
    var runningOpacity = 0.0
    var outroOpacity   = 0.0

    var stringAmps = [Double](repeating: 0, count: 6)
    var stringPhase = 0.0
    var brightness = [Double](repeating: 0, count: KB.count)

    let cycleLength = 30.0

    // Fingerpicked arpeggio over Am – F – C – G (key of C, vi–IV–I–V).
    private let chords: [[Int]] = [
        [45, 52, 57, 60, 64],   // Am
        [41, 48, 53, 57, 60],   // F
        [48, 55, 60, 64, 67],   // C
        [43, 50, 55, 59, 62],   // G
    ]
    private let arp = [0, 2, 3, 4, 3, 2]
    private let keyPath = [0, 7, 14, 3, 18, 10, 22, 5, 12, 1, 16, 8]

    private let runStart = 2.3
    private let runEnd   = 27.2
    private let step     = 0.30

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() {
        audio.prepareGuitar(chords.flatMap { $0 })
    }

    func showIdleFrame() { reset(); introOpacity = 1 }

    func start() {
        ticker?.invalidate(); reset(); buildTimeline()
        cycleStart = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() { ticker?.invalidate(); ticker = nil; audio.setVolume(1.0); showIdleFrame() }

    private func reset() {
        introOpacity = 1; runningOpacity = 0; outroOpacity = 0
        for i in stringAmps.indices { stringAmps[i] = 0 }
        for i in brightness.indices { brightness[i] = 0 }
        stringPhase = 0
        events = []; elapsed = 0; audio.setVolume(1.0)
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        stringPhase += 0.5
        for i in stringAmps.indices { stringAmps[i] *= 0.93 }
        for i in brightness.indices { brightness[i] *= 0.86 }
        while !events.isEmpty, events[0].t <= elapsed { events.removeFirst().run() }
        if elapsed >= cycleLength { reset(); buildTimeline(); cycleStart = CACurrentMediaTime() }
    }

    private func at(_ t: Double, _ run: @escaping () -> Void) {
        let ev = (t: t, run: run)
        if let idx = events.firstIndex(where: { $0.t > t }) { events.insert(ev, at: idx) }
        else { events.append(ev) }
    }

    private func stringFor(_ midi: Int) -> Int {
        max(0, min(5, 5 - (midi - 40) / 5))
    }

    private func buildTimeline() {
        at(runStart - 0.4) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.introOpacity = 0; self.runningOpacity = 1
            }
        }

        var t = runStart
        var ci = 0
        var keyCursor = 0
        while t < runEnd {
            let chord = chords[ci % chords.count]
            for degree in arp {
                let midi = chord[degree]
                let key = keyPath[keyCursor % keyPath.count]; keyCursor += 1
                at(t) {
                    self.stringAmps[self.stringFor(midi)] = 1.0
                    self.brightness[key] = 1.0
                    self.audio.playGuitar(midi: midi)
                }
                t += step
                if t >= runEnd { break }
            }
            ci += 1
        }

        at(runEnd + 0.1) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.runningOpacity = 0; self.outroOpacity = 1
            }
        }
    }
}

struct GuitarModeContent: View {
    let director: GuitarModeDirector

    var body: some View {
        ZStack {
            ShowcaseBackground()
            running.opacity(director.runningOpacity)
            intro.opacity(director.introOpacity)
            outro.opacity(director.outroOpacity)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var running: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)
            Text("GUITAR MODE")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(3).foregroundStyle(scAccent)
            Spacer().frame(height: 5)
            Text("every keystroke plucks a string")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer().frame(height: 4)
            Text("♪  fingerpicking")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Spacer().frame(height: 22)

            GuitarStrings(amps: director.stringAmps, phase: director.stringPhase)
                .frame(width: 320, height: 250)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.06), lineWidth: 1))
                )

            Spacer().frame(height: 24)
            ShowcaseKeyboard(brightness: director.brightness)
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            ShowcaseAppIcon(size: 104)
            Text("GUITAR MODE")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 14).tracking(1)
            Text("every key plucks a real string")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Label("sound on 🔊", systemImage: "guitars.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(scAccent)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.6))
                    .overlay(Capsule().strokeBorder(scAccent.opacity(0.4), lineWidth: 1)))
            Spacer()
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
                Text("TYPE.")
                Text("MAKE MUSIC.")
            }
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 16)
            .multilineTextAlignment(.center)
            Text("Guitar Mode · Karplus–Strong strings")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(scAccent)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

@Observable
final class GuitarModeHolder: @unchecked Sendable {
    let director = GuitarModeDirector()
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
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(GuitarModeContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct GuitarModeView: View {
    @State private var holder = GuitarModeHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            GuitarModeContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
