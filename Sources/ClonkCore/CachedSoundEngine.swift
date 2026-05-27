@preconcurrency import AVFoundation
import Foundation

// Lightweight playback backend used when the full live engine isn't needed.
//
// Trade-off vs SoundEngine (AVAudioEngine):
//   • No always-running graph → silent ⇒ truly 0% CPU.
//   • No real-time pitch / spatial / synthesis — every voice is a pre-
//     rendered AVAudioPCMBuffer loaded into an AVAudioPlayer.
//   • Pool of N players per voice, round-robined so rapid clicks don't
//     constantly interrupt themselves.
//
// The model promotes back to SoundEngine whenever a profile turns on
// piano, guitar, spatial, or per-key overrides — features this backend
// can't reproduce without effectively rebuilding AVAudioEngine.
@MainActor
final class CachedSoundEngine {
    // One "pool" per (kind × big?). Round-robin across the players inside;
    // each player owns one of the pre-rendered pitch-jittered variants.
    //
    // We rotate through ~3 players, each pre-set to a slightly different
    // volume so the resulting sequence still has subtle level variation
    // without paying an Obj-C `volume =` setter call per emit.
    private struct Pool {
        var players: [AVAudioPlayer] = []
        var next = 0
        var hasContent: Bool { !players.isEmpty }

        mutating func setBaseVolume(_ v: Float) {
            // Pre-jitter each player's volume around the base so the random
            // level variety is baked in, not re-applied per click.
            guard !players.isEmpty else { return }
            for (i, p) in players.enumerated() {
                let phase = Float(i) / Float(max(1, players.count - 1)) // 0…1
                let jitter = 0.82 + phase * 0.18 // 0.82…1.0
                p.volume = v * jitter
            }
        }

        mutating func play() {
            guard !players.isEmpty else { return }
            let p = players[next]
            next = (next + 1) % players.count
            // Always reset + play. Skipping the seek when mid-playback would
            // silently drop the click (AVAudioPlayer.play() on a still-playing
            // instance is a no-op). Round-robin ensures the seek almost always
            // happens on a finished player.
            p.currentTime = 0
            p.play()
        }
    }

    private var keyPress = Pool()
    private var keyRelease = Pool()
    private var keyBigPress = Pool()
    private var keyBigRelease = Pool()
    private var mousePress = Pool()
    private var mouseRelease = Pool()
    private var scrollPlay = Pool()

    private var keyHasRelease = false
    private var mouseHasRelease = false

    // Sample-pack key sound: one player per file in the pack, picked at
    // random per emit. Replaces keyPress entirely when active.
    private var samplePackPlayers: [AVAudioPlayer] = []
    private var usingSamplePack = false

    private var masterVolume: Float = 1
    private var keyVolume: Float = 1
    private var mouseVolume: Float = 1
    private var scrollVolume: Float = 1

    // MARK: - Public configuration

    func setMasterVolume(_ v: Double) {
        masterVolume = Float(max(0, min(1, v)))
        applyVolumes()
    }
    func setKeyVolume(_ v: Double) {
        keyVolume = Float(max(0, min(1, v)))
        applyVolumes()
    }
    func setMouseVolume(_ v: Double) {
        mouseVolume = Float(max(0, min(1, v)))
        applyVolumes()
    }
    func setScrollVolume(_ v: Double) {
        scrollVolume = Float(max(0, min(1, v)))
        applyVolumes()
    }

    // Push current volumes onto every pre-loaded player so playback hot path
    // doesn't need to touch `volume` per emit. Re-run on any volume change
    // or theme rebuild.
    private func applyVolumes() {
        let keyV = masterVolume * keyVolume
        keyPress.setBaseVolume(keyV)
        keyRelease.setBaseVolume(keyV)
        keyBigPress.setBaseVolume(keyV * 0.95)
        keyBigRelease.setBaseVolume(keyV * 0.95)
        let mouseV = masterVolume * mouseVolume
        mousePress.setBaseVolume(mouseV)
        mouseRelease.setBaseVolume(mouseV)
        scrollPlay.setBaseVolume(masterVolume * scrollVolume)
        let sampleV = masterVolume * keyVolume
        for (i, p) in samplePackPlayers.enumerated() {
            let phase = samplePackPlayers.count > 1
                ? Float(i) / Float(samplePackPlayers.count - 1) : 0
            p.volume = sampleV * (0.82 + phase * 0.18)
        }
    }

    func setKeyTheme(_ theme: Theme) {
        usingSamplePack = false
        samplePackPlayers = []
        let bank = ThemeBank.build(from: theme)
        keyPress = Self.pool(from: bank.press)
        keyRelease = Self.pool(from: bank.release)
        keyBigPress = Self.pool(from: bank.bigPress)
        keyBigRelease = Self.pool(from: bank.bigRelease)
        keyHasRelease = bank.hasRelease
        applyVolumes()
    }

    func setMouseTheme(_ theme: Theme) {
        let bank = ThemeBank.build(from: theme)
        mousePress = Self.pool(from: bank.press)
        mouseRelease = Self.pool(from: bank.release)
        mouseHasRelease = bank.hasRelease
        applyVolumes()
    }

    func setScrollTheme(_ theme: Theme) {
        let bank = ThemeBank.build(from: theme)
        scrollPlay = Self.pool(from: bank.press)
        applyVolumes()
    }

    func setKeySamplePack(_ pack: SamplePack?) {
        guard let pack else {
            usingSamplePack = false
            samplePackPlayers = []
            return
        }
        let files = SamplePackStore.audioFiles(in: pack.url)
        samplePackPlayers = files.compactMap { url -> AVAudioPlayer? in
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
            p.prepareToPlay()
            return p
        }
        usingSamplePack = !samplePackPlayers.isEmpty
        applyVolumes()
    }

    // MARK: - Playback

    func playKey(down: Bool, bigKey: Bool, keycode _: Int = -1) {
        if usingSamplePack {
            guard down, let player = samplePackPlayers.randomElement() else { return }
            player.currentTime = 0
            player.play()
            return
        }
        if !down && !keyHasRelease { return }
        switch (down, bigKey) {
        case (true, false):  keyPress.play()
        case (true, true):   keyBigPress.play()
        case (false, false): keyRelease.play()
        case (false, true):  keyBigRelease.play()
        }
    }

    func playMouse(down: Bool) {
        if !down && !mouseHasRelease { return }
        if down { mousePress.play() } else { mouseRelease.play() }
    }

    func playScroll() {
        scrollPlay.play()
    }

    // MARK: - Helpers

    // Convert a list of rendered PCM buffers to a Pool of warmed-up players.
    // Each buffer is round-tripped through a CAF in the temp dir to feed
    // AVAudioPlayer(data:) — AVAudioPlayer doesn't accept a buffer directly,
    // but it does keep its own internal copy so the file can be deleted.
    // ThemeBank renders 5 pitch-jittered variants per kind; we keep only 3.
    // Fewer concurrent AVAudioPlayers = less audio HAL coordination per
    // emit, and round-robin over 3 still gives plenty of polyphony for any
    // realistic typing speed (each click is ~50 ms; 3-cycle = 150 ms).
    private static func pool(from buffers: [AVAudioPCMBuffer]) -> Pool {
        let players = buffers.prefix(3).compactMap(player(from:))
        for p in players { p.prepareToPlay() }
        return Pool(players: players)
    }

    private static func player(from buffer: AVAudioPCMBuffer) -> AVAudioPlayer? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clonk-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
            try file.write(from: buffer)
            let data = try Data(contentsOf: url)
            return try AVAudioPlayer(data: data)
        } catch {
            return nil
        }
    }
}
