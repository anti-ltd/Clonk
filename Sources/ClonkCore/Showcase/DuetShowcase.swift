// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #7 — "Piano × Guitar" duet. 9:16, ~30 s loop. Clonk plays both at
// once: a piano melody (Beethoven's "Ode to Joy", public domain) on top, a
// guitar arpeggio underneath — piano lights the keyboard/roll, guitar plucks
// the strings, both voiced by the real PianoSynth + GuitarSynth.
// NOT-@MainActor director (see ReelScene.swift header).

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

@Observable
final class DuetDirector: @unchecked Sendable, ReelDirecting {

    var introOpacity   = 1.0
    var runningOpacity = 0.0
    var outroOpacity   = 0.0

    // Piano voice.
    var clock = 0.0
    var litNotes: Set<Int> = []
    // Guitar voice.
    var stringAmps = [Double](repeating: 0, count: 6)
    var stringPhase = 0.0

    let cycleLength = 30.0

    // Ode to Joy melody (key of C), piano.
    private let pianoPattern = [
        64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62,
        64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 62, 60, 60,
    ]
    // Under it, the guitar arpeggiates C and G, switching every two beats.
    private let chordC = [48, 55, 60, 64]
    private let chordG = [43, 50, 55, 59]

    fileprivate var pianoNotes: [ShowNote] = []

    private let runStart = 2.3
    private let runEnd   = 27.0
    private let step     = 0.36

    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() {
        pianoNotes = tileMelody(pianoPattern, from: runStart, to: runEnd, step: step)
        audio.preparePiano(pianoNotes.map(\.midi))
        audio.prepareGuitar(chordC + chordG)
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
        for i in stringAmps.indices { stringAmps[i] = 0 }
        stringPhase = 0
        events = []; elapsed = 0; audio.setVolume(1.0)
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        clock = elapsed
        stringPhase += 0.5
        for i in stringAmps.indices { stringAmps[i] *= 0.92 }
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

        for (i, note) in pianoNotes.enumerated() {
            // Piano melody on the beat.
            at(note.t) {
                self.litNotes.insert(note.midi)
                self.audio.playPiano(midi: note.midi)
            }
            at(note.t + 0.30) { self.litNotes.remove(note.midi) }

            // Guitar arpeggio: two plucks per beat from the active chord.
            let chord = (i / 2) % 2 == 0 ? chordC : chordG
            let g1 = chord[i % chord.count]
            let g2 = chord[(i + 2) % chord.count]
            at(note.t) {
                self.stringAmps[self.stringFor(g1)] = 1.0
                self.audio.playGuitar(midi: g1)
            }
            at(note.t + step * 0.5) {
                self.stringAmps[self.stringFor(g2)] = 0.85
                self.audio.playGuitar(midi: g2)
            }
        }

        at(runEnd + 0.1) {
            withAnimation(.easeInOut(duration: 0.6)) {
                self.runningOpacity = 0; self.outroOpacity = 1
            }
        }
    }
}

struct DuetContent: View {
    let director: DuetDirector

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

    private var sectionLabel: some View {
        Text("PIANO × GUITAR")
            .font(.system(size: 16, weight: .black, design: .rounded))
            .tracking(3).foregroundStyle(scAccent)
    }

    private var running: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)
            sectionLabel
            Spacer().frame(height: 3)
            Text("playing a duet · Ode to Joy")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Spacer().frame(height: 14)

            // Piano half.
            VStack(spacing: 0) {
                PianoRoll(notes: director.pianoNotes, clock: director.clock, lookahead: 2.2)
                    .frame(width: 320, height: 150)
                PianoKeyboard(lit: director.litNotes)
                    .frame(width: 320, height: 60)
            }

            Spacer().frame(height: 14)
            HStack(spacing: 8) {
                Image(systemName: "guitars.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(scAccent)
                Text("GUITAR").font(.system(size: 11, weight: .black, design: .rounded)).tracking(2).foregroundStyle(.white.opacity(0.5))
            }
            Spacer().frame(height: 8)

            // Guitar half.
            GuitarStrings(amps: director.stringAmps, phase: director.stringPhase)
                .frame(width: 320, height: 150)
                .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06), lineWidth: 1)))

            Spacer(minLength: 8)
            ShowcaseFooter().padding(.bottom, 24)
        }
        .frame(width: 360, height: 640)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            ShowcaseAppIcon(size: 104)
            VStack(spacing: -2) {
                Text("PIANO")
                Text("× GUITAR")
            }
            .font(.system(size: 36, weight: .heavy, design: .rounded))
            .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 14)
            .multilineTextAlignment(.center)
            Text("one keyboard. both at once.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Label("sound on 🔊", systemImage: "music.note")
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
                Text("A WHOLE BAND.")
                Text("ONE KEYBOARD.")
            }
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(.white).shadow(color: scAccent.opacity(0.4), radius: 16)
            .multilineTextAlignment(.center)
            Text("Piano + Guitar Mode")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(scAccent)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

@Observable
final class DuetHolder: @unchecked Sendable {
    let director = DuetDirector()
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
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(DuetContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct DuetView: View {
    @State private var holder = DuetHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            DuetContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
