import AVFoundation

// Real-time playback. A pool of player nodes feeds one mixer, giving the
// polyphony needed for fast typing (each node is one voice, round-robined).
@MainActor
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let voiceCount = 6

    private var keyBank: ThemeBank
    private var mouseBank: ThemeBank
    private var scrollBank: ThemeBank

    // Cache of per-key / per-button override banks, keyed by "<themeID>|<pitch>".
    private var overrideBanks: [String: ThemeBank] = [:]

    // Per-category volume — multiplies into the per-voice node level.
    private var keyVolume: Float = 1
    private var mouseVolume: Float = 1
    private var scrollVolume: Float = 1
    private var keySamples: SampleBank?      // non-nil when a sample pack drives keys
    private var running = false

    init() {
        keyBank = ThemeBank.build(from: Theme.builtIn(id: Theme.defaultID))
        mouseBank = ThemeBank.build(from: Theme.mouseClick)
        scrollBank = ThemeBank.build(from: Theme.scrollVoices[0])
        configure()
    }

    private func configure() {
        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.prepare()
        start()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    // MARK: - Configuration

    func setVolume(_ v: Double) {
        engine.mainMixerNode.outputVolume = Float(max(0, min(1, v)))
    }

    func setKeyVolume(_ v: Double) { keyVolume = Float(max(0, min(1, v))) }
    func setMouseVolume(_ v: Double) { mouseVolume = Float(max(0, min(1, v))) }
    func setScrollVolume(_ v: Double) { scrollVolume = Float(max(0, min(1, v))) }

    func setKeyTheme(_ theme: Theme) {
        keySamples = nil
        keyBank = ThemeBank.build(from: theme)
    }

    func setMouseTheme(_ theme: Theme) {
        mouseBank = ThemeBank.build(from: theme)
    }

    func setScrollTheme(_ theme: Theme) {
        scrollBank = ThemeBank.build(from: theme)
    }

    func clearOverrideCache() {
        overrideBanks.removeAll()
    }

    private func overrideBank(_ theme: Theme, _ basePitch: Double) -> ThemeBank {
        let key = "\(theme.id)|\(String(format: "%.3f", basePitch))"
        if let cached = overrideBanks[key] { return cached }
        let built = ThemeBank.build(from: theme, basePitch: basePitch)
        overrideBanks[key] = built
        return built
    }

    func setKeySamplePack(_ pack: SamplePack?) {
        guard let pack else { keySamples = nil; return }
        let bank = SampleBank.load(pack, format: format)
        keySamples = bank.isEmpty ? nil : bank
    }

    var usingSamplePack: Bool { keySamples != nil }

    // MARK: - Playback

    func playKey(down: Bool, bigKey: Bool, override: Theme? = nil, basePitch: Double = 1.0) {
        if let override {
            let bank = overrideBank(override, basePitch)
            if !down && !bank.hasRelease { return }
            emit(down ? bank.pressBuffer(big: bigKey) : bank.releaseBuffer(big: bigKey),
                 level: keyLevel() * keyVolume)
            return
        }
        if let samples = keySamples {
            guard down, let buffer = samples.randomBuffer() else { return }
            emit(buffer, level: keyLevel() * keyVolume)
            return
        }
        if !down && !keyBank.hasRelease { return }
        emit(down ? keyBank.pressBuffer(big: bigKey) : keyBank.releaseBuffer(big: bigKey),
             level: keyLevel() * keyVolume)
    }

    func playMouse(down: Bool, override: Theme? = nil, basePitch: Double = 1.0) {
        let bank = override.map { overrideBank($0, basePitch) } ?? mouseBank
        if !down && !bank.hasRelease { return }
        emit(down ? bank.pressBuffer(big: false) : bank.releaseBuffer(big: false),
             level: mouseVolume)
    }

    func playScroll(override: Theme? = nil, basePitch: Double = 1.0) {
        let bank = override.map { overrideBank($0, basePitch) } ?? scrollBank
        emit(bank.pressBuffer(big: false), level: keyLevel() * scrollVolume)
    }

    // Slight random level per click so repeated sounds never machine-gun.
    private func keyLevel() -> Float { Float.random(in: 0.78...1.0) }

    private func emit(_ buffer: AVAudioPCMBuffer, level: Float) {
        if !running { start() }
        guard running else { return }
        let node = players[next]
        next = (next + 1) % players.count
        node.volume = level
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }
}
