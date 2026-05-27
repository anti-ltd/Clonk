import AVFoundation

// Real-time playback. A pool of player nodes feeds an environment node
// (for optional 3D spatialisation) into the main mixer, giving the
// polyphony needed for fast typing (each node is one voice, round-robined).
@MainActor
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    // 4 voices is plenty for click polyphony: each click is ~50 ms, so even
    // 30 keys/sec recycles voices comfortably (interrupted older clicks are
    // mostly inaudible).
    private let voiceCount = 4
    // Whether players are currently routed *through* the env node (spatial
    // on) or straight to the main mixer (spatial off — skips a DSP layer
    // per click).
    private var routedThroughEnv = false

    private var keyBank: ThemeBank
    private var mouseBank: ThemeBank
    private var scrollBank: ThemeBank

    private var overrideBanks: [String: ThemeBank] = [:]

    private var keyVolume: Float = 1
    private var mouseVolume: Float = 1
    private var scrollVolume: Float = 1
    private var keySamples: SampleBank?
    private var running = false
    // Idle pause: AVAudioEngine running consumes a few % CPU even when
    // playing nothing. Pause the engine after a stretch of silence and
    // bring it back on the next emit().
    private var idleTimer: Timer?
    private var lastEmitAt: Date = .distantPast
    // Aggressive pause — while `engine.isRunning`, the audio IOThread runs
    // a real-time render cycle pulling silence through the graph for ~2-4%
    // CPU. Pausing fast keeps idle low; the engine restarts in <50 ms on
    // the next emit, which the brain doesn't perceive as latency.
    private static let idlePause: TimeInterval = 1.5

    private var spatial = SpatialConfig()

    private let pianoBank = PianoBank()
    private var pianoConfig = PianoConfig()
    private var pianoEnabled = false

    private let guitarBank = GuitarBank()
    private var guitarConfig = GuitarConfig()
    private var guitarEnabled = false

    init() {
        keyBank = ThemeBank.build(from: Theme.builtIn(id: Theme.defaultID))
        mouseBank = ThemeBank.build(from: Theme.mouseClick)
        scrollBank = ThemeBank.build(from: Theme.scrollVoices[0])
        configure()
    }

    private func configure() {
        engine.attach(env)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.renderingAlgorithm = .equalPowerPanning
        env.distanceAttenuationParameters.distanceAttenuationModel = .linear
        env.distanceAttenuationParameters.referenceDistance = 0.5
        env.distanceAttenuationParameters.maximumDistance = 4
        env.reverbParameters.enable = false

        for _ in 0..<voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            // Default to bypassing the environment node — spatial defaults to
            // off, and routing through env adds per-click DSP. `applySpatial`
            // re-wires the graph if the user enables spatial.
            engine.connect(node, to: engine.mainMixerNode, format: monoFormat)
            players.append(node)
        }
        routedThroughEnv = false
        engine.prepare()
        start()

        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    // Wire each player either through the environment node (3D / HRTF) or
    // straight to the main mixer (no spatial). Reconnecting is safe while
    // the engine is running per AVAudioEngine docs.
    private func setRouteThroughEnv(_ on: Bool) {
        guard on != routedThroughEnv else { return }
        for p in players {
            engine.disconnectNodeOutput(p)
            engine.connect(p, to: on ? env : engine.mainMixerNode, format: monoFormat)
        }
        routedThroughEnv = on
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

    func applySpatial(_ cfg: SpatialConfig) {
        spatial = cfg
        setRouteThroughEnv(cfg.enabled)
        guard cfg.enabled else { return }
        let algo: AVAudio3DMixingRenderingAlgorithm =
            cfg.hrtf ? .HRTF : .equalPowerPanning
        for player in players {
            player.renderingAlgorithm = algo
        }
        env.renderingAlgorithm = algo
    }

    private func overrideBank(_ theme: Theme, _ basePitch: Double) -> ThemeBank {
        let key = "\(theme.id)|\(String(format: "%.3f", basePitch))"
        if let cached = overrideBanks[key] { return cached }
        let built = ThemeBank.build(from: theme, basePitch: basePitch)
        overrideBanks[key] = built
        return built
    }

    func setPianoMode(_ enabled: Bool, config: PianoConfig) {
        pianoEnabled = enabled
        pianoConfig = config
        if enabled {
            pianoBank.rebuildIfNeeded(config)
        }
    }

    var isPianoMode: Bool { pianoEnabled }

    func playPianoKey(keycode: Int, big: Bool) {
        guard let buffer = pianoBank.buffer(for: keycode) else { return }
        emit(buffer,
             level: keyLevel() * keyVolume * (big ? 0.95 : 1.0),
             position: spatialPosition(keycode: keycode))
    }

    func previewPiano(_ config: PianoConfig) {
        let buffer = pianoBank.previewBuffer(config)
        emit(buffer, level: keyVolume, position: nil)
    }

    func setGuitarMode(_ enabled: Bool, config: GuitarConfig) {
        guitarEnabled = enabled
        guitarConfig = config
        if enabled {
            guitarBank.rebuildIfNeeded(config)
        }
    }

    var isGuitarMode: Bool { guitarEnabled }

    func playGuitarKey(keycode: Int, big: Bool) {
        guard let buffer = guitarBank.buffer(for: keycode) else { return }
        emit(buffer,
             level: keyLevel() * keyVolume * (big ? 0.95 : 1.0),
             position: spatialPosition(keycode: keycode))
    }

    func previewGuitar(_ config: GuitarConfig) {
        let buffer = guitarBank.previewBuffer(config)
        emit(buffer, level: keyVolume, position: nil)
    }

    func setKeySamplePack(_ pack: SamplePack?) {
        guard let pack else { keySamples = nil; return }
        let bank = SampleBank.load(pack, format: monoFormat)
        keySamples = bank.isEmpty ? nil : bank
    }

    var usingSamplePack: Bool { keySamples != nil }

    // MARK: - Playback

    func playKey(down: Bool, bigKey: Bool, override: Theme? = nil, basePitch: Double = 1.0, keycode: Int = -1) {
        if let override {
            let bank = overrideBank(override, basePitch)
            if !down && !bank.hasRelease { return }
            emit(down ? bank.pressBuffer(big: bigKey) : bank.releaseBuffer(big: bigKey),
                 level: keyLevel() * keyVolume,
                 position: spatialPosition(keycode: keycode))
            return
        }
        if let samples = keySamples {
            guard down, let buffer = samples.randomBuffer() else { return }
            emit(buffer, level: keyLevel() * keyVolume,
                 position: spatialPosition(keycode: keycode))
            return
        }
        if !down && !keyBank.hasRelease { return }
        emit(down ? keyBank.pressBuffer(big: bigKey) : keyBank.releaseBuffer(big: bigKey),
             level: keyLevel() * keyVolume,
             position: spatialPosition(keycode: keycode))
    }

    func playMouse(down: Bool, override: Theme? = nil, basePitch: Double = 1.0) {
        let bank = override.map { overrideBank($0, basePitch) } ?? mouseBank
        if !down && !bank.hasRelease { return }
        emit(down ? bank.pressBuffer(big: false) : bank.releaseBuffer(big: false),
             level: mouseVolume, position: nil)
    }

    func playScroll(override: Theme? = nil, basePitch: Double = 1.0) {
        let bank = override.map { overrideBank($0, basePitch) } ?? scrollBank
        emit(bank.pressBuffer(big: false), level: keyLevel() * scrollVolume, position: nil)
    }

    private func keyLevel() -> Float { Float.random(in: 0.78...1.0) }

    private func emit(_ buffer: AVAudioPCMBuffer, level: Float, position: AVAudio3DPoint?) {
        if !running { start() }
        guard running else { return }
        let node = players[next]
        next = (next + 1) % players.count
        node.volume = level
        // Only touch `position` when spatial is engaged. The default (0,0,0)
        // is set at configure time and never moves while spatial is off, so
        // skipping the assignment shaves an Obj-C call from every emit.
        if let position {
            node.position = position
        }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !node.isPlaying { node.play() }
        bumpIdleTimer()
    }

    // Idle pause uses a single self-rescheduling timer rather than tearing
    // down and rebuilding one on every emit (run-loop churn at high
    // click rates). Each emit just stamps `lastEmitAt`; the timer checks
    // elapsed time when it fires and either pauses the engine or
    // re-arms for the remainder.
    private func bumpIdleTimer() {
        lastEmitAt = Date()
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idlePause, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTick() }
        }
    }

    private func idleTick() {
        idleTimer = nil
        let elapsed = Date().timeIntervalSince(lastEmitAt)
        if elapsed >= Self.idlePause {
            pauseIfIdle()
        } else {
            // Activity since the timer was armed — re-arm for the remainder.
            let remaining = max(0.1, Self.idlePause - elapsed)
            idleTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.idleTick() }
            }
        }
    }

    // Public: force-pause the live engine. Used when the model switches
    // to the cached backend so the live IO thread stops spinning.
    func pause() {
        idleTimer?.invalidate()
        idleTimer = nil
        pauseIfIdle()
    }

    private func pauseIfIdle() {
        guard engine.isRunning else { return }
        // If any player is still mid-buffer, defer the pause briefly.
        if players.contains(where: { $0.isPlaying }) {
            // Some nodes report isPlaying=true with no scheduled audio
            // remaining. Stop them so the engine can quiesce.
            for p in players { p.stop() }
        }
        engine.pause()
        running = false
    }

    // Maps a keycode to a position on the virtual keyboard plane. When
    // spatial is off (or the keycode is unknown), returns nil so the
    // emitter uses centre.
    private func spatialPosition(keycode: Int) -> AVAudio3DPoint? {
        guard spatial.enabled, keycode >= 0 else { return nil }
        // Use the home row as the widest reference. Find the key in any
        // row and compute its normalized x.
        for row in KeyboardLayout.rows {
            let totalUnits = row.reduce(0.0) { $0 + $1.width }
            var unitOffset = 0.0
            for k in row {
                if k.keycode == keycode {
                    let centerUnits = unitOffset + k.width / 2
                    let normalized = (centerUnits / totalUnits) * 2 - 1
                    let width = Float(spatial.width)
                    let distance = Float(0.3 + spatial.distance * 1.7)
                    return AVAudio3DPoint(
                        x: Float(normalized) * width * distance,
                        y: 0,
                        z: -distance
                    )
                }
                unitOffset += k.width
            }
        }
        return nil
    }
}
