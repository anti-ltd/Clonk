import Foundation
import Testing

@testable import ClonkCore

// Profile is forward-compatible: older saved JSON files (lacking newer keys)
// must decode cleanly with defaults filled in, and a full round-trip must
// preserve every setting.
@Suite("Profile JSON coding")
struct ProfileCodingTests {

    @Test("Empty-ish JSON decodes with defaults") @MainActor
    func decodesMinimalJSON() throws {
        let json = #"""
        { "id": "abc", "name": "Test" }
        """#
        let data = Data(json.utf8)
        let p = try JSONDecoder().decode(Profile.self, from: data)

        #expect(p.id == "abc")
        #expect(p.name == "Test")
        // Spot-check that every field hit its default rather than nil-ing out.
        #expect(p.keySoundEnabled == true)
        #expect(p.releaseSoundEnabled == true)
        #expect(p.themeID == "tactile")
        #expect(p.volume == 0.7)
        #expect(p.releaseSuppressInterval == 0.085)
        #expect(p.enginePlaybackMode == .cached)
        #expect(p.pianoModeEnabled == false)
        #expect(p.guitarModeEnabled == false)
    }

    @Test("Round-trip preserves every field") @MainActor
    func roundTripPreservesEverything() throws {
        var p = Profile(id: "p1", name: "Round-trip")
        p.keySoundEnabled = false
        p.mouseSoundEnabled = false
        p.releaseSoundEnabled = false
        p.muteModifiers = true
        p.volume = 0.42
        p.keyVolume = 0.91
        p.mouseVolume = 0.33
        p.scrollVolume = 0.12
        p.themeID = "thock"
        p.samplePackID = "pack-uuid"
        p.releaseSuppressInterval = 0.2
        p.enginePlaybackMode = .live
        p.pianoModeEnabled = true
        p.guitarModeEnabled = true
        p.keyVizEnabled = true
        p.wpmVizEnabled = true
        p.cpmVizEnabled = true
        p.statsEnabled = true

        let data = try JSONEncoder().encode(p)
        let q = try JSONDecoder().decode(Profile.self, from: data)
        #expect(q == p)
    }

    @Test("Unknown keys are ignored") @MainActor
    func ignoresUnknownKeys() throws {
        let json = #"""
        {
            "id": "x", "name": "X",
            "_futureFlag": true,
            "_futureNumber": 99
        }
        """#
        let p = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(p.id == "x")
        #expect(p.name == "X")
    }
}
