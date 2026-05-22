import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

// Central controller: owns the sound engine and the global key listener,
// holds all user settings, and keeps both wired together.
//
// Settings live in a Profile (see Profile.swift). The active profile is
// loaded from disk on launch and mutations sync back to it. Users may
// keep multiple profiles and switch between them instantly.
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let engine = SoundEngine()
    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private let stats = StatsRecorder()
    @ObservationIgnored private let wpmMeter = WPMMeter()
    @ObservationIgnored private var accessibilityTimer: Timer?
    @ObservationIgnored private var lastPressAt: Date?
    @ObservationIgnored private var pressIntervalEMA: Double = 0.4
    @ObservationIgnored private var scrollAccum: Double = 0
    // Per-keycode timestamp of last keyDown / autorepeat. Used to
    // recover from missed keyUp events (app focus switches, eaten
    // keystrokes) that would otherwise leave a key visually stuck.
    @ObservationIgnored private var keyLastDownAt: [Int: Date] = [:]
    // Keycodes for the modifier keys we receive as toggles via
    // .flagsChanged rather than discrete down/up events.
    @ObservationIgnored private static let modifierKeycodes: Set<Int> =
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 113]
    @ObservationIgnored private var wpmTimer: Timer?
    @ObservationIgnored private var secureInputTimer: Timer?
    @ObservationIgnored private var triggers: TriggersManager
    @ObservationIgnored private var keyVizWindow: OverlayWindow<KeyVisualizerView>?
    @ObservationIgnored private var wpmVizWindow: OverlayWindow<WPMVisualizerView>?

    // Slider 0…1 mapped to detent size — low sensitivity = sparse ticks.
    private var scrollDetent: Double { 60.0 - active.scrollSensitivity * 54.0 }

    // MARK: - Profile-backed state

    // The single source of truth for every persisted setting. Every UI
    // binding reads/writes through `active`; mutations are saved to disk.
    var active: Profile {
        didSet {
            if active.id != oldValue.id {
                ProfileStore.activeID = active.id
            }
            ProfileStore.save(active)
            propagateToEngine(old: oldValue)
        }
    }

    private(set) var profiles: [Profile] = []

    // MARK: - Convenience bindings (read/write directly on `active`)

    var keySoundEnabled: Bool {
        get { active.keySoundEnabled } set { active.keySoundEnabled = newValue }
    }
    var mouseSoundEnabled: Bool {
        get { active.mouseSoundEnabled } set { active.mouseSoundEnabled = newValue }
    }
    var releaseSoundEnabled: Bool {
        get { active.releaseSoundEnabled } set { active.releaseSoundEnabled = newValue }
    }
    var mouseReleaseEnabled: Bool {
        get { active.mouseReleaseEnabled } set { active.mouseReleaseEnabled = newValue }
    }
    var muteModifiers: Bool {
        get { active.muteModifiers } set { active.muteModifiers = newValue }
    }
    var scrollSoundEnabled: Bool {
        get { active.scrollSoundEnabled } set { active.scrollSoundEnabled = newValue }
    }
    var scrollSensitivity: Double {
        get { active.scrollSensitivity } set { active.scrollSensitivity = newValue }
    }
    var keyboardAdvancedEnabled: Bool {
        get { active.keyboardAdvancedEnabled } set { active.keyboardAdvancedEnabled = newValue }
    }
    var mouseAdvancedEnabled: Bool {
        get { active.mouseAdvancedEnabled } set { active.mouseAdvancedEnabled = newValue }
    }
    var scrollAdvancedEnabled: Bool {
        get { active.scrollAdvancedEnabled } set { active.scrollAdvancedEnabled = newValue }
    }
    var advanced: AdvancedConfig {
        get { active.advanced } set { active.advanced = newValue }
    }
    var mouseThemeID: String {
        get { active.mouseThemeID } set { active.mouseThemeID = newValue }
    }
    var scrollThemeID: String {
        get { active.scrollThemeID } set { active.scrollThemeID = newValue }
    }
    var volume: Double {
        get { active.volume } set { active.volume = newValue }
    }
    var keyVolume: Double {
        get { active.keyVolume } set { active.keyVolume = newValue }
    }
    var mouseVolume: Double {
        get { active.mouseVolume } set { active.mouseVolume = newValue }
    }
    var scrollVolume: Double {
        get { active.scrollVolume } set { active.scrollVolume = newValue }
    }
    var themeID: String {
        get { active.themeID } set { active.themeID = newValue }
    }
    var samplePackID: String? {
        get { active.samplePackID } set { active.samplePackID = newValue }
    }
    var triggersConfig: TriggersConfig {
        get { active.triggers }
        set {
            active.triggers = newValue
            triggers.update(newValue)
        }
    }
    var spatialConfig: SpatialConfig {
        get { active.spatial }
        set {
            active.spatial = newValue
            engine.applySpatial(newValue)
        }
    }
    var statsEnabled: Bool {
        get { active.statsEnabled } set { active.statsEnabled = newValue }
    }
    var pianoModeEnabled: Bool {
        get { active.pianoModeEnabled }
        set {
            active.pianoModeEnabled = newValue
            if newValue { active.keyboardAdvancedEnabled = false }
        }
    }
    var pianoConfig: PianoConfig {
        get { active.piano } set { active.piano = newValue }
    }
    var keyVizEnabled: Bool {
        get { active.keyVizEnabled }
        set { active.keyVizEnabled = newValue; refreshKeyViz() }
    }
    var keyVizStyle: KeyVizStyle {
        get { active.keyVizStyle }
        set {
            guard active.keyVizStyle != newValue else { return }
            active.keyVizStyle = newValue
            // Rebuild the window so the new style gets its own
            // default position / remembered frame.
            refreshKeyViz(forceRebuild: true)
        }
    }
    var wpmVizEnabled: Bool {
        get { active.wpmVizEnabled }
        set { active.wpmVizEnabled = newValue; refreshWPMViz() }
    }

    // MARK: - Runtime state

    private(set) var accessibilityGranted = false
    private(set) var installedPacks: [SamplePack] = []
    private(set) var pressedKeys: Set<Int> = []
    private(set) var recentKeyEvents: [KeyPressEvent] = []
    private(set) var pressedMouseButtons: Set<Int> = []
    private(set) var scrollPulses: [String: Int] = ["up": 0, "down": 0]
    @ObservationIgnored private(set) var recentTyping: String = ""
    private(set) var currentWPM: Double = 0
    private(set) var wpmHistory: [Double] = Array(repeating: 0, count: 80)
    @ObservationIgnored private(set) var secureInputActive: Bool = false

    static let customID = "custom"
    static let pianoID = "piano"
    var isCustom: Bool { themeID == Self.customID }
    var currentTheme: Theme { Theme.builtIn(id: themeID) }
    var activePack: SamplePack? { installedPacks.first { $0.id == samplePackID } }
    var monitorRunning: Bool { monitor.isRunning }
    private(set) var statsVersion: Int = 0
    var statsSnapshot: StatsSnapshot {
        _ = statsVersion
        return stats.snapshot
    }
    var triggersManager: TriggersManager { triggers }

    // True iff any sleep trigger says we should be silent.
    var isMuted: Bool { triggers.isMuted }

    init() {
        let loaded = ProfileStore.all()
        let initialActive: Profile
        if let activeID = ProfileStore.activeID,
           let found = loaded.first(where: { $0.id == activeID }) {
            initialActive = found
        } else if let first = loaded.first {
            initialActive = first
        } else {
            let p = Profile(id: ProfileStore.newID(), name: "Default")
            ProfileStore.save(p)
            initialActive = p
        }
        active = initialActive
        profiles = ProfileStore.all()
        ProfileStore.activeID = initialActive.id

        triggers = TriggersManager(config: initialActive.triggers)
        installedPacks = SamplePackStore.installed()

        triggers.onChange = { [weak self] in self?.onTriggersChanged() }
        propagateToEngine(old: nil)
        wireMonitor()
    }

    // MARK: - Lifecycle

    func start() {
        refreshAccessibility()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
        triggers.start()
        beginAuxTimers()
        refreshKeyViz()
        refreshWPMViz()
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

    // MARK: - Profiles

    func reloadProfiles() {
        profiles = ProfileStore.all()
    }

    func switchProfile(to id: String) {
        if let next = ProfileStore.all().first(where: { $0.id == id }) {
            active = next
        }
    }

    func duplicateActive() {
        var copy = active
        copy.id = ProfileStore.newID()
        copy.name = active.name + " Copy"
        ProfileStore.save(copy)
        reloadProfiles()
    }

    func newProfile(named name: String) {
        let p = Profile(id: ProfileStore.newID(), name: name)
        ProfileStore.save(p)
        reloadProfiles()
        active = p
    }

    func rename(profileID id: String, to name: String) {
        if active.id == id {
            active.name = name
            return
        }
        if var p = profiles.first(where: { $0.id == id }) {
            p.name = name
            ProfileStore.save(p)
            reloadProfiles()
        }
    }

    func deleteProfile(_ id: String) {
        ProfileStore.delete(id)
        reloadProfiles()
        if active.id == id, let next = profiles.first {
            active = next
        } else if profiles.isEmpty {
            let p = Profile(id: ProfileStore.newID(), name: "Default")
            ProfileStore.save(p)
            reloadProfiles()
            active = p
        }
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

    func previewPiano() {
        engine.setPianoMode(true, config: pianoConfig)
        engine.previewPiano(pianoConfig)
    }

    // Plays a key event respecting all sound settings. Shared by the global
    // listener and the in-app sound playground.
    func playKeyEvent(down: Bool, bigKey: Bool, modifier: Bool, keycode: Int = -1) {
        if keycode >= 0 {
            if modifier {
                let wasPressed = pressedKeys.contains(keycode)
                if wasPressed {
                    pressedKeys.remove(keycode)
                    recordKeyRelease(keycode: keycode)
                } else {
                    pressedKeys.insert(keycode)
                    recordKeyPress(keycode: keycode)
                }
            } else {
                if down {
                    pressedKeys.insert(keycode)
                    recordKeyPress(keycode: keycode)
                } else {
                    pressedKeys.remove(keycode)
                    recordKeyRelease(keycode: keycode)
                }
            }
        }

        if down && !modifier {
            recordTyping(keycode: keycode)
        }

        guard keySoundEnabled else { return }
        if isMuted { return }
        if modifier && muteModifiers { return }

        let override = (keyboardAdvancedEnabled ? advanced.keys[keycode] : nil)
            .flatMap { o in Theme.any(id: o.themeID).map { ($0, o.pitchMul) } }

        if down {
            if !modifier { updateTypingRate() }
            if pianoModeEnabled {
                engine.playPianoKey(keycode: keycode, big: bigKey)
                return
            }
            engine.playKey(down: true, bigKey: bigKey,
                           override: override?.0, basePitch: override?.1 ?? 1.0,
                           keycode: keycode)
        } else {
            guard releaseSoundEnabled else { return }
            if pianoModeEnabled { return }
            if pressIntervalEMA < 0.085 { return }
            engine.playKey(down: false, bigKey: bigKey,
                           override: override?.0, basePitch: override?.1 ?? 1.0,
                           keycode: keycode)
        }
    }

    private func recordKeyPress(keycode: Int) {
        let label = KeyboardLayout.name(for: keycode)
        let display = label == "Space" ? "␣" : label
        let event = KeyPressEvent(keycode: keycode, label: display, pressedAt: Date(), releasedAt: nil)
        recentKeyEvents.append(event)
        // Cap to keep array small.
        if recentKeyEvents.count > 24 {
            recentKeyEvents.removeFirst(recentKeyEvents.count - 24)
        }
        keyLastDownAt[keycode] = Date()
    }

    private func recordKeyRelease(keycode: Int) {
        let now = Date()
        // Mark the most recent unreleased event for this keycode.
        if let i = recentKeyEvents.lastIndex(where: { $0.keycode == keycode && $0.releasedAt == nil }) {
            recentKeyEvents[i].releasedAt = now
        }
        keyLastDownAt.removeValue(forKey: keycode)
    }

    // Sweep keys that look stuck — i.e. still marked pressed but with
    // no autorepeat / release for a while. Skips modifiers which come
    // through as flagsChanged toggles and can be legitimately held.
    private func sweepStuckKeys() {
        if pressedKeys.isEmpty { return }
        let now = Date()
        let nonModifierTimeout: TimeInterval = 1.5
        let stuck = pressedKeys.filter { kc in
            guard !Self.modifierKeycodes.contains(kc) else { return false }
            let last = keyLastDownAt[kc] ?? .distantPast
            return now.timeIntervalSince(last) > nonModifierTimeout
        }
        for kc in stuck {
            pressedKeys.remove(kc)
            recordKeyRelease(keycode: kc)
        }
    }

    // Periodic pruner: drop fully-faded events so the minimal overlay
    // animates them out smoothly instead of snapping when an arbitrary
    // event happens to release.
    private func pruneFadedKeyEvents() {
        // Skip when nothing to do — touching recentKeyEvents at all
        // would invalidate any @Observable consumers.
        if recentKeyEvents.isEmpty { return }
        let now = Date()
        var kept: [KeyPressEvent] = []
        kept.reserveCapacity(recentKeyEvents.count)
        for e in recentKeyEvents {
            if let r = e.releasedAt, now.timeIntervalSince(r) > 1.0 { continue }
            kept.append(e)
        }
        if kept.count != recentKeyEvents.count {
            recentKeyEvents = kept
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

    private func recordTyping(keycode: Int) {
        if statsEnabled { stats.recordKey(keycode); statsVersion &+= 1 }
        wpmMeter.recordChar()
        if !secureInputActive {
            let ch = KeyboardLayout.name(for: keycode)
            if ch.count == 1 || ch == "Space" {
                let glyph = ch == "Space" ? " " : ch
                recentTyping.append(glyph)
                if recentTyping.count > 64 { recentTyping.removeFirst(recentTyping.count - 64) }
            }
        }
    }

    func playMouseEvent(down: Bool, button: Int = 0) {
        if down { pressedMouseButtons.insert(button) } else { pressedMouseButtons.remove(button) }
        if down && statsEnabled { stats.recordMouse(); statsVersion &+= 1 }
        guard mouseSoundEnabled else { return }
        if isMuted { return }
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

    func handleScroll(dx: Double, dy: Double) {
        let magnitude = abs(dx) + abs(dy)
        guard magnitude > 0 else { return }
        scrollAccum += magnitude
        var ticks = 0
        while scrollAccum >= scrollDetent && ticks < 3 {
            scrollAccum -= scrollDetent
            let dir = dy >= 0 ? "up" : "down"
            scrollPulses[dir, default: 0] += 1
            if statsEnabled { stats.recordScroll(); statsVersion &+= 1 }
            if scrollSoundEnabled && !isMuted {
                let override = (scrollAdvancedEnabled ? advanced.scroll[dir] : nil)
                    .flatMap { o in Theme.any(id: o.themeID).map { ($0, o.pitchMul) } }
                engine.playScroll(override: override?.0, basePitch: override?.1 ?? 1.0)
            }
            ticks += 1
        }
        if scrollAccum > scrollDetent * 4 { scrollAccum = 0 }
    }

    // MARK: - Stats helpers

    func resetStats() { stats.reset(); statsVersion &+= 1 }
    func exportStatsCSV() -> String { stats.exportCSV() }

    // MARK: - Internals

    private func propagateToEngine(old: Profile?) {
        // Push every cached setting through to the audio engine.
        engine.setVolume(active.volume)
        engine.setKeyVolume(active.keyVolume)
        engine.setMouseVolume(active.mouseVolume)
        engine.setScrollVolume(active.scrollVolume)
        engine.setMouseTheme(Theme.mouseVoice(id: active.mouseThemeID))
        engine.setScrollTheme(Theme.scrollVoice(id: active.scrollThemeID))
        applyKeyVoice()
        engine.setPianoMode(active.pianoModeEnabled, config: active.piano)
        engine.applySpatial(active.spatial)
        // Trigger config diff: only push if a different profile loaded.
        if let old, old.id != active.id {
            triggers.update(active.triggers)
        }
    }

    private func applyKeyVoice() {
        if isCustom {
            if let pack = activePack {
                engine.setKeySamplePack(pack)
            } else {
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
        monitor.onKeyRepeat = { [weak self] keycode in
            // Hold-down refresh: bump the last-seen time so the stuck-
            // key sweep doesn't free a key the user is still holding.
            self?.keyLastDownAt[keycode] = Date()
        }
        monitor.onMouse = { [weak self] down, button in
            self?.playMouseEvent(down: down, button: button)
        }
        monitor.onScroll = { [weak self] dx, dy in
            self?.handleScroll(dx: dx, dy: dy)
        }
    }

    private func onTriggersChanged() {
        // Nothing to push to engine — the `isMuted` flag is checked at
        // event time. UI observers update through @Observable read.
        _ = isMuted
    }

    // MARK: - Auxiliary timers (WPM sampling, secure-input poll)

    private func beginAuxTimers() {
        wpmTimer?.invalidate()
        wpmTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleWPM() }
        }
        secureInputTimer?.invalidate()
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSecureInput() }
        }
    }

    private func sampleWPM() {
        sweepStuckKeys()
        pruneFadedKeyEvents()
        let raw = wpmMeter.current
        // If nothing observes WPM and the user isn't typing, short-
        // circuit so we don't churn @Observable storage every 250ms.
        if raw == 0 && currentWPM < 0.05 && !wpmVizEnabled && !statsEnabled {
            return
        }
        // EMA smoothing so the line glides instead of jittering.
        let next = currentWPM * 0.6 + raw * 0.4
        if abs(next - currentWPM) > 0.01 {
            currentWPM = next
        }
        // Only maintain the history when the sparkline is actually
        // visible — every append invalidates the array.
        if wpmVizEnabled {
            wpmHistory.append(currentWPM)
            if wpmHistory.count > 80 { wpmHistory.removeFirst(wpmHistory.count - 80) }
        }
        if statsEnabled && currentWPM > 0 {
            let oldPeak = stats.snapshot.peakWPM
            stats.recordWPM(currentWPM)
            if stats.snapshot.peakWPM != oldPeak { statsVersion &+= 1 }
        }
    }

    private func refreshSecureInput() {
        secureInputActive = IsSecureEventInputEnabled()
    }

    // MARK: - Visualizer windows

    private func refreshKeyViz(forceRebuild: Bool = false) {
        if forceRebuild, let win = keyVizWindow {
            win.persist()
            win.orderOut(nil)
            keyVizWindow = nil
        }
        if active.keyVizEnabled {
            if keyVizWindow == nil {
                let style = active.keyVizStyle
                let size: NSSize
                let defaultRect: NSRect
                switch style {
                case .full:
                    size = NSSize(width: 380, height: 180)
                    defaultRect = NSRect(x: 100, y: 100, width: size.width, height: size.height)
                case .minimal:
                    size = NSSize(width: 260, height: 56)
                    // Bottom-center of the main screen.
                    if let screen = NSScreen.main {
                        let frame = screen.visibleFrame
                        let x = frame.midX - size.width / 2
                        let y = frame.minY + 60
                        defaultRect = NSRect(x: x, y: y, width: size.width, height: size.height)
                    } else {
                        defaultRect = NSRect(x: 100, y: 100, width: size.width, height: size.height)
                    }
                }
                let win = OverlayWindow(
                    name: "keyviz.\(style.rawValue)",
                    size: size,
                    defaultRect: defaultRect
                ) {
                    KeyVisualizerView(model: self)
                }
                keyVizWindow = win
                win.show()
            }
        } else {
            keyVizWindow?.persist()
            keyVizWindow?.orderOut(nil)
            keyVizWindow = nil
        }
    }

    #if APPSTAGE
    // Seed visual-only state for overlay screenshots without running the live
    // input pipeline (which requires Accessibility permission).
    func seedOverlayState(wpm: Double = 85, pressedKeycodes: [Int] = [38, 40, 37]) {
        let wave: [Double] = stride(from: 0, to: 80, by: 1).map { i in
            let t = Double(i) / 79.0
            return max(0, wpm * (0.65 + sin(t * .pi * 4.5) * 0.22 + Double.random(in: -0.06...0.06)))
        }
        wpmHistory = wave
        currentWPM = wpm
        pressedKeys = Set(pressedKeycodes)
        let now = Date()
        recentKeyEvents = pressedKeycodes.enumerated().map { idx, code in
            KeyPressEvent(
                keycode: code,
                label: KeyboardLayout.name(for: code),
                pressedAt: now.addingTimeInterval(-Double(idx) * 0.04)
            )
        }
    }
    #endif

    private func refreshWPMViz() {
        if active.wpmVizEnabled {
            if wpmVizWindow == nil {
                let win = OverlayWindow(name: "wpmviz", size: NSSize(width: 260, height: 80)) {
                    WPMVisualizerView(model: self)
                }
                wpmVizWindow = win
                win.show()
            }
        } else {
            wpmVizWindow?.persist()
            wpmVizWindow?.orderOut(nil)
            wpmVizWindow = nil
        }
    }
}
