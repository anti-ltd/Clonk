// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #5 — "Piano Mode". 9:16, ~30 s loop. Clonk plays Beethoven's
// "Für Elise" (public domain) on Piano Mode: notes rain down a Synthesia roll
// and light a drawn keyboard, voiced by the real PianoSynth. NOT-@MainActor
// director (see ReelScene.swift header); recorded via the shared ReelRecorder.

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

@Observable
final class PianoModeDirector: @unchecked Sendable, ReelDirecting {

    var introOpacity   = 1.0
    var runningOpacity = 0.0
    var outroOpacity   = 0.0

    var clock = 0.0
    var litNotes: Set<Int> = []

    let cycleLength = 30.0

    // Für Elise — opening, as MIDI note numbers.
    private let pattern = [
        76, 75, 76, 75, 76, 71, 74, 72, 69,
        60, 64, 69, 71,
        64, 68, 71, 72,
        64, 76, 75, 76, 75, 76, 71, 74, 72, 69,
        60, 64, 69, 71,
        64, 72, 71, 69,
    ]
    fileprivate var melody: [ShowNote] = []

    private let runStart = 2.3
    private let runEnd   = 27.2
    private let step     = 0.26

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() {
        melody = tileMelody(pattern, from: runStart, to: runEnd, step: step)
        audio.preparePiano(melody.map(\.midi))
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
        clock = 0; litNotes = []
        events = []; elapsed = 0; audio.setVolume(1.0)
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        clock = elapsed
        while !events.isEmpty, events[0].t <= elapsed { events.removeFirst().run() }
        if elapsed >= cycleLength { reset(); buildTimeline(); cycleStart = CACurrentMediaTime() }
    }

    private func at(_ t: Double, _ run: @escaping () -> Void) {
        let ev = (t: t, run: run)
        if let idx = events.firstIndex(where: { $0.t > t }) { events.insert(ev, at: idx) }
        else { events.append(ev) }
    }

    private func buildTimeline() {
        at(runStart - 0.4) {
            withAnimation(.easeInOut(duration: 0.5)) {
                self.introOpacity = 0; self.runningOpacity = 1
            }
        }
        for note in melody {
            at(note.t) {
                self.litNotes.insert(note.midi)
                self.audio.playPiano(midi: note.midi)
            }
            at(note.t + 0.22) { self.litNotes.remove(note.midi) }
        }
        at(runEnd + 0.1) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.runningOpacity = 0; self.outroOpacity = 1
            }
        }
    }
}

struct PianoModeContent: View {
    let director: PianoModeDirector

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
            Spacer().frame(height: 40)
            Text("PIANO MODE")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(3).foregroundStyle(scAccent)
            Spacer().frame(height: 5)
            Text("your keyboard, but a grand piano")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer().frame(height: 4)
            Text("♪  Für Elise")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Spacer().frame(height: 14)
            VStack(spacing: 0) {
                PianoRoll(notes: director.melody, clock: director.clock)
                    .frame(width: 320, height: 300)
                PianoKeyboard(lit: director.litNotes)
                    .frame(width: 320, height: 78)
                    .shadow(color: scAccent.opacity(0.3), radius: 14)
            }
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            ShowcaseAppIcon(size: 104)
            Text("PIANO MODE")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 14).tracking(1)
            Text("every key is a piano note")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Label("sound on 🔊", systemImage: "pianokeys")
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
                Text("PLAY YOUR")
                Text("KEYBOARD.")
            }
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 16)
            .multilineTextAlignment(.center)
            Text("Piano Mode · any scale, any key")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(scAccent)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

@Observable
final class PianoModeHolder: @unchecked Sendable {
    let director = PianoModeDirector()
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
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(PianoModeContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct PianoModeView: View {
    @State private var holder = PianoModeHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            PianoModeContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
