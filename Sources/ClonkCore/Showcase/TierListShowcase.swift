// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Showcase #2 — "Switch Tier-List". 9:16, ~30 s loop.
// Fast and opinionated: rate every Clonk switch, slam down an S/A/B stamp with
// its real sound, then a final tier board + "which one are you? 👇" to farm
// comments. Same NOT-@MainActor director pattern as the reel (see header of
// ReelScene.swift); recorded via the shared ReelRecorder.

#if CLONK_SHOWCASE

import AppKit
import QuartzCore
import SwiftUI

private enum Tier: String { case s = "S", a = "A", b = "B"
    var color: Color {
        switch self {
        case .s: return Color(red: 1.0, green: 0.72, blue: 0.12)   // gold
        case .a: return Color(red: 0.35, green: 0.85, blue: 0.45)  // green
        case .b: return Color(red: 0.40, green: 0.62, blue: 1.0)   // blue
        }
    }
}

private struct RatedSwitch {
    let themeId: String
    let name: String
    let tier: Tier
}

@Observable
final class TierListDirector: @unchecked Sendable, ReelDirecting {

    var introOpacity   = 1.0
    var runningOpacity = 0.0
    var outroOpacity   = 0.0

    var index = 0
    var nameOpacity = 0.0
    var nameOffset: CGFloat = 18

    // Tier stamp.
    var stampOpacity = 0.0
    var stampScale: CGFloat = 2.6
    var brightness = [Double](repeating: 0, count: KB.count)

    let cycleLength = 30.0

    fileprivate let rated: [RatedSwitch] = [
        .init(themeId: "thock",      name: "DEEP THOCK",         tier: .s),
        .init(themeId: "creamy",     name: "CREAMY LINEAR",      tier: .s),
        .init(themeId: "marble",     name: "MARBLE PLATE",       tier: .a),
        .init(themeId: "clicky",     name: "CLICKY BLUE",        tier: .a),
        .init(themeId: "typewriter", name: "VINTAGE TYPEWRITER", tier: .b),
        .init(themeId: "tactile",    name: "TACTILE BROWN",      tier: .a),
        .init(themeId: "hollow",     name: "HOLLOW CASE",        tier: .b),
        .init(themeId: "glass",      name: "GLASS TAP",          tier: .a),
    ]

    fileprivate var current: RatedSwitch { rated[min(index, rated.count - 1)] }

    private let keyPath = [4, 9, 13, 1, 7, 18, 2, 11, 24, 0, 15, 6]
    private var events: [(t: Double, run: () -> Void)] = []
    private var elapsed = 0.0
    private var cycleStart: CFTimeInterval = 0
    private var ticker: Timer?
    private let audio = ReelAudio()

    init() { audio.prepareThemes(rated.map(\.themeId)) }

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
        index = 0; nameOpacity = 0; nameOffset = 18
        stampOpacity = 0; stampScale = 2.6
        for i in brightness.indices { brightness[i] = 0 }
        events = []; elapsed = 0; audio.setVolume(1.0)
    }

    private func tick() {
        elapsed = CACurrentMediaTime() - cycleStart
        for i in brightness.indices { brightness[i] *= 0.82 }
        while !events.isEmpty, events[0].t <= elapsed { events.removeFirst().run() }
        if elapsed >= cycleLength { reset(); buildTimeline(); cycleStart = CACurrentMediaTime() }
    }

    private func at(_ t: Double, _ run: @escaping () -> Void) {
        let ev = (t: t, run: run)
        if let idx = events.firstIndex(where: { $0.t > t }) { events.insert(ev, at: idx) }
        else { events.append(ev) }
    }

    private func buildTimeline() {
        let introEnd: Double = 1.9
        let outroLen: Double = 5.4
        let span = cycleLength - introEnd - outroLen
        let segment = span / Double(rated.count)   // ~2.84 s each

        at(introEnd - 0.35) {
            withAnimation(.easeInOut(duration: 0.45)) {
                self.introOpacity = 0; self.runningOpacity = 1
            }
        }

        var keyCursor = 0
        for (i, sw) in rated.enumerated() {
            let s = introEnd + Double(i) * segment

            at(s) {
                self.index = i
                self.nameOpacity = 0; self.nameOffset = 18
                self.stampOpacity = 0; self.stampScale = 2.6
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.nameOpacity = 1; self.nameOffset = 0
                }
            }

            // Two quick sound taps as we "audition" the switch.
            for k in 0..<2 {
                let key = keyPath[keyCursor % keyPath.count]; keyCursor += 1
                at(s + 0.35 + Double(k) * 0.4) {
                    self.brightness[key] = 1.0
                    self.audio.play(themeId: sw.themeId, down: true, bigKey: false)
                }
                at(s + 0.35 + Double(k) * 0.4 + 0.16) {
                    self.audio.play(themeId: sw.themeId, down: false, bigKey: false)
                }
            }

            // The verdict: tier letter slams down with a deep thock.
            at(s + segment - 1.25) {
                self.stampScale = 2.6; self.stampOpacity = 0
                withAnimation(.spring(response: 0.3, dampingFraction: 0.58)) {
                    self.stampOpacity = 1; self.stampScale = 1.0
                }
                self.audio.play(themeId: "thock", down: true, bigKey: true)
            }
        }

        // Outro: tier board + comment bait.
        let outroStart = introEnd + Double(rated.count) * segment
        at(outroStart - 0.3) {
            withAnimation(.easeInOut(duration: 0.55)) {
                self.runningOpacity = 0; self.outroOpacity = 1
            }
        }
    }
}

// MARK: - Views

private struct TierStamp: View {
    let tier: String
    let color: Color
    var body: some View {
        Text(tier)
            .font(.system(size: 96, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 150, height: 150)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.black.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(color, lineWidth: 5))
                    .shadow(color: color.opacity(0.6), radius: 22)
            )
            .rotationEffect(.degrees(-8))
    }
}

private struct TierRow: View {
    let tier: Tier
    let names: [String]
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(tier.rawValue)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(tier.color))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(names, id: \.self) { n in
                    Text(n)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(tier.color.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tier.color.opacity(0.4), lineWidth: 1)))
    }
}

struct TierListContent: View {
    let director: TierListDirector

    var body: some View {
        ZStack {
            ShowcaseBackground()
            runningView.opacity(director.runningOpacity)
            introView.opacity(director.introOpacity)
            outroView.opacity(director.outroOpacity)
        }
        .frame(width: 360, height: 640)
        .clipped()
    }

    private var runningView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 46)
            Text("SWITCH TIER LIST")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(3).foregroundStyle(scAccent)
            Spacer().frame(height: 26)

            Text(director.current.name)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: scAccent.opacity(0.4), radius: 12)
                .opacity(director.nameOpacity)
                .offset(y: director.nameOffset)
                .frame(height: 34)

            Spacer().frame(height: 26)
            ZStack {
                TierStamp(tier: director.current.tier.rawValue, color: director.current.tier.color)
                    .scaleEffect(director.stampScale)
                    .opacity(director.stampOpacity)
            }
            .frame(height: 180)

            Spacer().frame(height: 22)
            ShowcaseKeyboard(brightness: director.brightness)
            Spacer(minLength: 10)
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var introView: some View {
        VStack(spacing: 16) {
            Spacer()
            ShowcaseAppIcon(size: 104)
            Text("RATING EVERY\nCLONK SWITCH")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: scAccent.opacity(0.4), radius: 14)
            Text("S · A · B tier")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(scAccent).tracking(3)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }

    private var outroView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 54)
            Text("THE FULL RANKING")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(3).foregroundStyle(scAccent)
            Spacer().frame(height: 8)
            ForEach([Tier.s, Tier.a, Tier.b], id: \.rawValue) { tier in
                TierRow(tier: tier,
                        names: director.rated.filter { $0.tier == tier }.map(\.name))
            }
            .padding(.horizontal, 22)
            Spacer().frame(height: 14)
            Text("which one are you? 👇")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: scAccent.opacity(0.5), radius: 10)
            Spacer()
            ShowcaseFooter().padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
    }
}

// MARK: - Holder + preview window

@Observable
final class TierListHolder: @unchecked Sendable {
    let director = TierListDirector()
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
            let rec = ReelRecorder(director: d, makeRootView: { AnyView(TierListContent(director: d)) })
            recorder = rec; isRecording = true
            Task { await rec.start() }
        }
    }
}

public struct TierListView: View {
    @State private var holder = TierListHolder()
    public init() {}
    public var body: some View {
        VStack(spacing: 0) {
            TierListContent(director: holder.director).frame(width: 360, height: 640)
            ShowcaseControls(isPlaying: holder.isPlaying, isRecording: holder.isRecording,
                             onPlay: { holder.togglePlay() }, onRecord: { holder.toggleRecord() })
        }
        .frame(width: 360)
    }
}

#endif
