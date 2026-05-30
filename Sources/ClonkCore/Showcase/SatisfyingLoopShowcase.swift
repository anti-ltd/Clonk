// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #4 — "Oddly Satisfying". 9:16, seamless 30 s loop. No talking:
// diagonal waves of light ripple across the keyboard to a steady soft click,
// built to be rewatched. The brightness field is a pure function of elapsed
// time with integer sweeps per cycle, so the loop point is invisible.
// NOT-@MainActor director (see ReelScene.swift header); shared ReelRecorder.

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

@Observable
final class SatisfyingLoopDirector: @unchecked Sendable, ReelDirecting {

    var brightness = [Double](repeating: 0, count: KB.count)

    let cycleLength = 30.0

    private let sweeps = 12.0     // integer sweeps per cycle → seamless wrap
    private let range  = 14.0     // diagonal travel distance
    private let bandW  = 1.5      // half-width of each lit band
    private let clickInterval = 0.3

    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private var lastClickStep = -1
    private let audio = ReelAudio()

    init() {
        audio.prepareThemes(["creamy", "thock"])
    }

    func showIdleFrame() {
        elapsed = 0; lastClickStep = -1
        computeWave(0)
    }

    func start() {
        ticker?.invalidate()
        lastClickStep = -1
        audio.setVolume(0.7)              // calm
        cycleStart = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stop() {
        ticker?.invalidate(); ticker = nil
        audio.setVolume(1.0)
        showIdleFrame()
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        if elapsed >= cycleLength {
            cycleStart = CACurrentMediaTime()
            elapsed = 0
            lastClickStep = -1
        }
        computeWave(elapsed)

        // Steady soft click — interval divides 30 s, so the rhythm loops cleanly.
        let step = Int(elapsed / clickInterval)
        if step != lastClickStep {
            lastClickStep = step
            audio.play(themeId: step % 2 == 0 ? "creamy" : "thock", down: true, bigKey: false)
        }
    }

    private func band(_ diag: Double, _ pos: Double) -> Double {
        var d = abs(diag - pos)
        d = min(d, range - d)             // wrap distance → seamless across the cut
        return max(0, 1 - d / bandW)
    }

    private func computeWave(_ t: Double) {
        let frac = (t / cycleLength * sweeps).truncatingRemainder(dividingBy: 1.0)
        let pos1 = frac * range
        let pos2 = ((frac + 0.5).truncatingRemainder(dividingBy: 1.0)) * range
        for i in 0..<KB.count {
            let diag = KB.column[i] + KB.rowOf[i] * 1.4
            let v = band(diag, pos1) + 0.55 * band(diag, pos2)
            brightness[i] = min(1.0, v)
        }
    }
}

// MARK: - Content

struct SatisfyingLoopContent: View {
    let director: SatisfyingLoopDirector

    var body: some View {
        ZStack {
            ShowcaseBackground(glow: 0.16)
            VStack {
                Spacer()
                ShowcaseKeyboard(brightness: director.brightness, keyW: 30, keyH: 34, gap: 4)
                    .shadow(color: scAccent.opacity(0.25), radius: 40)
                Spacer()
            }
            VStack {
                Spacer()
                ShowcaseFooter().opacity(0.6).padding(.bottom, 30)
            }
            // Soft top/bottom vignette for a premium frame.
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }
}

// MARK: - Holder + preview window

@Observable
final class SatisfyingLoopHolder: @unchecked Sendable {
    let director = SatisfyingLoopDirector()
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
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(SatisfyingLoopContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct SatisfyingLoopView: View {
    @State private var holder = SatisfyingLoopHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            SatisfyingLoopContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
