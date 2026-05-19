import Foundation
import Observation

// Central controller: owns the sound engine and the global key listener,
// holds all user settings, and keeps both wired together.
@MainActor
@Observable
final class AppModel {
    private enum K {
        static let keySound = "keySoundEnabled"
        static let mouseSound = "mouseSoundEnabled"
        static let releaseSound = "releaseSoundEnabled"
        static let mouseRelease = "mouseReleaseEnabled"
        static let muteModifiers = "muteModifiers"
        static let scrollSound = "scrollSoundEnabled"
        static let scrollSensitivity = "scrollSensitivity"
        static let keyVolume = "keyVolume"
        static let mouseVolume = "mouseVolume"
        static let scrollVolume = "scrollVolume"
        static let keyboardAdvanced = "keyboardAdvancedEnabled"
        static let mouseAdvanced = "mouseAdvancedEnabled"
        static let scrollAdvanced = "scrollAdvancedEnabled"
        static let volume = "volume"
        static let theme = "themeID"
        static let pack = "samplePackID"
        static let mouseTheme = "mouseThemeID"
        static let scrollTheme = "scrollThemeID"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let engine = SoundEngine()
    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private var accessibilityTimer: Timer?
    @ObservationIgnored private var lastPressAt: Date?
    @ObservationIgnored private var pressIntervalEMA: Double = 0.4
    @ObservationIgnored private var scrollAccum: Double = 0

    // Slider 0…1 mapped to detent size — low sensitivity = sparse ticks.
    private var scrollDetent: Double { 60.0 - scrollSensitivity * 54.0 }

    var keySoundEnabled: Bool { didSet { defaults.set(keySoundEnabled, forKey: K.keySound) } }
    var mouseSoundEnabled: Bool { didSet { defaults.set(mouseSoundEnabled, forKey: K.mouseSound) } }
    var releaseSoundEnabled: Bool { didSet { defaults.set(releaseSoundEnabled, forKey: K.releaseSound) } }
    var mouseReleaseEnabled: Bool { didSet { defaults.set(mouseReleaseEnabled, forKey: K.mouseRelease) } }
    var muteModifiers: Bool { didSet { defaults.set(muteModifiers, forKey: K.muteModifiers) } }
    var scrollSoundEnabled: Bool { didSet { defaults.set(scrollSoundEnabled, forKey: K.scrollSound) } }
    var scrollSensitivity: Double { didSet { defaults.set(scrollSensitivity, forKey: K.scrollSensitivity) } }

    var keyboardAdvancedEnabled: Bool { didSet { defaults.set(keyboardAdvancedEnabled, forKey: K.keyboardAdvanced) } }
    var mouseAdvancedEnabled: Bool { didSet { defaults.set(mouseAdvancedEnabled, forKey: K.mouseAdvanced) } }
    var scrollAdvancedEnabled: Bool { didSet { defaults.set(scrollAdvancedEnabled, forKey: K.scrollAdvanced) } }

    var advanced: AdvancedConfig {
        didSet { advanced.save() }
    }

    var mouseThemeID: String {
        didSet {
            defaults.set(mouseThemeID, forKey: K.mouseTheme)
            engine.setMouseTheme(Theme.mouseVoice(id: mouseThemeID))
        }
    }

    var scrollThemeID: String {
        didSet {
            defaults.set(scrollThemeID, forKey: K.scrollTheme)
            engine.setScrollTheme(Theme.scrollVoice(id: scrollThemeID))
        }
    }

    var volume: Double {
        didSet {
            defaults.set(volume, forKey: K.volume)
            engine.setVolume(volume)
        }
    }

    var keyVolume: Double {
        didSet {
            defaults.set(keyVolume, forKey: K.keyVolume)
            engine.setKeyVolume(keyVolume)
        }
    }
    var mouseVolume: Double {
        didSet {
            defaults.set(mouseVolume, forKey: K.mouseVolume)
            engine.setMouseVolume(mouseVolume)
        }
    }
    var scrollVolume: Double {
        didSet {
            defaults.set(scrollVolume, forKey: K.scrollVolume)
            engine.setScrollVolume(scrollVolume)
        }
    }

    var themeID: String {
        didSet {
            defaults.set(themeID, forKey: K.theme)
            applyKeyVoice()
        }
    }

    // nil → procedural theme drives keys; otherwise the named sample pack does.
    var samplePackID: String? {
        didSet {
            defaults.set(samplePackID, forKey: K.pack)
            applyKeyVoice()
        }
    }

    private(set) var accessibilityGranted = false
    private(set) var installedPacks: [SamplePack] = []

    // Live input state — drives the Advanced editors' visualisations.
    private(set) var pressedKeys: Set<Int> = []
    private(set) var pressedMouseButtons: Set<Int> = []
    private(set) var scrollPulses: [String: Int] = ["up": 0, "down": 0]

    // The "Custom" voice — drives keys from an imported sample pack.
    static let customID = "custom"
    var isCustom: Bool { themeID == Self.customID }

    var currentTheme: Theme { Theme.builtIn(id: themeID) }
    var activePack: SamplePack? { installedPacks.first { $0.id == samplePackID } }
    var monitorRunning: Bool { monitor.isRunning }

    init() {
        keySoundEnabled = defaults.object(forKey: K.keySound) as? Bool ?? true
        mouseSoundEnabled = defaults.object(forKey: K.mouseSound) as? Bool ?? true
        releaseSoundEnabled = defaults.object(forKey: K.releaseSound) as? Bool ?? true
        mouseReleaseEnabled = defaults.object(forKey: K.mouseRelease) as? Bool ?? true
        muteModifiers = defaults.object(forKey: K.muteModifiers) as? Bool ?? false
        scrollSoundEnabled = defaults.object(forKey: K.scrollSound) as? Bool ?? true
        scrollSensitivity = defaults.object(forKey: K.scrollSensitivity) as? Double ?? 0.35
        volume = defaults.object(forKey: K.volume) as? Double ?? 0.7
        keyVolume = defaults.object(forKey: K.keyVolume) as? Double ?? 1.0
        mouseVolume = defaults.object(forKey: K.mouseVolume) as? Double ?? 1.0
        scrollVolume = defaults.object(forKey: K.scrollVolume) as? Double ?? 1.0
        themeID = defaults.string(forKey: K.theme) ?? Theme.defaultID
        samplePackID = defaults.string(forKey: K.pack)
        mouseThemeID = defaults.string(forKey: K.mouseTheme) ?? Theme.mouseClick.id
        scrollThemeID = defaults.string(forKey: K.scrollTheme) ?? Theme.scrollDefaultID
        keyboardAdvancedEnabled = defaults.object(forKey: K.keyboardAdvanced) as? Bool ?? false
        mouseAdvancedEnabled = defaults.object(forKey: K.mouseAdvanced) as? Bool ?? false
        scrollAdvancedEnabled = defaults.object(forKey: K.scrollAdvanced) as? Bool ?? false
        advanced = AdvancedConfig.load()

        installedPacks = SamplePackStore.installed()
        engine.setVolume(volume)
        engine.setKeyVolume(keyVolume)
        engine.setMouseVolume(mouseVolume)
        engine.setScrollVolume(scrollVolume)
        engine.setMouseTheme(Theme.mouseVoice(id: mouseThemeID))
        engine.setScrollTheme(Theme.scrollVoice(id: scrollThemeID))
        applyKeyVoice()
        wireMonitor()
    }

    // MARK: - Lifecycle

    func start() {
        refreshAccessibility()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
    }

    func refreshAccessibility() {
        accessibilityGranted = KeyMonitor.accessibilityGranted
        if accessibilityGranted {
            if !monitor.isRunning { monitor.start() }
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        }
    }

    func requestAccessibility() {
        KeyMonitor.promptForAccessibility()
    }

    // MARK: - Sample packs

    func reloadPacks() {
        installedPacks = SamplePackStore.installed()
        if let id = samplePackID, !installedPacks.contains(where: { $0.id == id }) {
            samplePackID = nil
        }
    }

    func importPack(from url: URL) throws {
        let pack = try SamplePackStore.importFolder(url)
        installedPacks = SamplePackStore.installed()
        themeID = Self.customID
        samplePackID = pack.id
    }

    func deletePack(_ pack: SamplePack) {
        SamplePackStore.delete(pack)
        if samplePackID == pack.id { samplePackID = nil }
        installedPacks = SamplePackStore.installed()
    }

    // MARK: - Preview

    func preview() {
        engine.playKey(down: true, bigKey: false)
    }

    // Plays a key event respecting all sound settings. Shared by the global
    // listener and the in-app sound playground.
    func playKeyEvent(down: Bool, bigKey: Bool, modifier: Bool, keycode: Int = -1) {
        // Track press state for the visualiser. Flagged events come as a
        // single press click, so toggle the held set on each one.
        if keycode >= 0 {
            if modifier {
                if pressedKeys.contains(keycode) { pressedKeys.remove(keycode) }
                else { pressedKeys.insert(keycode) }
            } else {
                if down { pressedKeys.insert(keycode) } else { pressedKeys.remove(keycode) }
            }
        }

        guard keySoundEnabled else { return }
        if modifier && muteModifiers { return }

        let override = (keyboardAdvancedEnabled ? advanced.keys[keycode] : nil)
            .flatMap { o in Theme.any(id: o.themeID).map { ($0, o.pitchMul) } }

        if down {
            if !modifier { updateTypingRate() }
            engine.playKey(down: true, bigKey: bigKey,
                           override: override?.0, basePitch: override?.1 ?? 1.0)
        } else {
            guard releaseSoundEnabled else { return }
            if pressIntervalEMA < 0.085 { return }
            engine.playKey(down: false, bigKey: bigKey,
                           override: override?.0, basePitch: override?.1 ?? 1.0)
        }
    }

    private func updateTypingRate() {
        let now = Date()
        if let last = lastPressAt {
            let dt = min(now.timeIntervalSince(last), 1.0)
            pressIntervalEMA = pressIntervalEMA * 0.55 + dt * 0.45
        }
        lastPressAt = now
    }

    func playMouseEvent(down: Bool, button: Int = 0) {
        if down { pressedMouseButtons.insert(button) } else { pressedMouseButtons.remove(button) }
        guard mouseSoundEnabled else { return }
        if !down && !mouseReleaseEnabled { return }
        let override = (mouseAdvancedEnabled ? advanced.mouse[button] : nil)
            .flatMap { o in Theme.any(id: o.themeID).map { ($0, o.pitchMul) } }
        engine.playMouse(down: down, override: override?.0, basePitch: override?.1 ?? 1.0)
    }

    func previewMouse() {
        engine.playMouse(down: true)
    }

    func previewScroll() {
        engine.playScroll()
    }

    // Used by the Advanced editors to audition a candidate override.
    func previewOverride(theme: Theme, basePitch: Double) {
        engine.playKey(down: true, bigKey: false, override: theme, basePitch: basePitch)
    }

    func setKeyOverride(_ keycode: Int, _ override: VoiceOverride?) {
        var cfg = advanced
        if let override { cfg.keys[keycode] = override } else { cfg.keys.removeValue(forKey: keycode) }
        advanced = cfg
    }

    func setMouseOverride(_ button: Int, _ override: VoiceOverride?) {
        var cfg = advanced
        if let override { cfg.mouse[button] = override } else { cfg.mouse.removeValue(forKey: button) }
        advanced = cfg
    }

    func setScrollOverride(_ direction: String, _ override: VoiceOverride?) {
        var cfg = advanced
        if let override { cfg.scroll[direction] = override } else { cfg.scroll.removeValue(forKey: direction) }
        advanced = cfg
    }

    // Accumulates raw scroll delta and emits one detent "tick" per notch's
    // worth of movement — recreating the feel of a physical scroll wheel.
    func handleScroll(dx: Double, dy: Double) {
        let magnitude = abs(dx) + abs(dy)
        guard magnitude > 0 else { return }
        scrollAccum += magnitude
        var ticks = 0
        while scrollAccum >= scrollDetent && ticks < 3 {
            scrollAccum -= scrollDetent
            let dir = dy >= 0 ? "up" : "down"
            scrollPulses[dir, default: 0] += 1
            if scrollSoundEnabled {
                let override = (scrollAdvancedEnabled ? advanced.scroll[dir] : nil)
                    .flatMap { o in Theme.any(id: o.themeID).map { ($0, o.pitchMul) } }
                engine.playScroll(override: override?.0, basePitch: override?.1 ?? 1.0)
            }
            ticks += 1
        }
        if scrollAccum > scrollDetent * 4 { scrollAccum = 0 }
    }

    // MARK: - Internals

    private func applyKeyVoice() {
        if isCustom {
            if let pack = activePack {
                engine.setKeySamplePack(pack)
            } else {
                // Custom selected but no pack imported yet — stay audible.
                engine.setKeyTheme(Theme.builtIn(id: Theme.defaultID))
            }
        } else {
            engine.setKeyTheme(currentTheme)
        }
    }

    private func wireMonitor() {
        monitor.onKey = { [weak self] down, big, modifier, keycode in
            self?.playKeyEvent(down: down, bigKey: big, modifier: modifier, keycode: keycode)
        }
        monitor.onMouse = { [weak self] down, button in
            self?.playMouseEvent(down: down, button: button)
        }
        monitor.onScroll = { [weak self] dx, dy in
            self?.handleScroll(dx: dx, dy: dy)
        }
    }
}
