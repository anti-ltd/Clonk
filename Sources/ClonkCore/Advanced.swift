import Foundation

// One key's (or button's, or scroll-direction's) custom sound recipe — the
// theme to play and how far to detune it.
struct VoiceOverride: Codable, Equatable {
    var themeID: String
    var pitchMul: Double = 1.0
}

// All per-key / per-button / per-direction overrides for "Advanced" mode.
// Lives in UserDefaults as JSON.
struct AdvancedConfig: Codable, Equatable {
    var keys: [Int: VoiceOverride] = [:]       // keycode → override
    var mouse: [Int: VoiceOverride] = [:]      // 0=left, 1=right, 2=other
    var scroll: [String: VoiceOverride] = [:]  // "up", "down"

    static let storageKey = "advancedConfig"

    static func load() -> AdvancedConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cfg = try? JSONDecoder().decode(AdvancedConfig.self, from: data) else {
            return AdvancedConfig()
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AdvancedConfig.storageKey)
        }
    }
}
