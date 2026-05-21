import Foundation

// A Profile is a named snapshot of every Clonk setting. Users can keep
// several (e.g. "Loud at home", "Quiet in cafe", "Streaming") and switch
// instantly. The active profile ID is remembered across launches.
//
// Storage: one JSON file per profile under
//   ~/Library/Application Support/counter-ltd/clonk/Profiles/<id>.json
// Plus a sidecar "active" file holding the current ID.
struct Profile: Codable, Identifiable, Equatable {
    var id: String
    var name: String

    // Sound enablement
    var keySoundEnabled: Bool = true
    var mouseSoundEnabled: Bool = true
    var releaseSoundEnabled: Bool = true
    var mouseReleaseEnabled: Bool = true
    var muteModifiers: Bool = false
    var scrollSoundEnabled: Bool = true
    var scrollSensitivity: Double = 0.35

    // Volumes
    var volume: Double = 0.7
    var keyVolume: Double = 1.0
    var mouseVolume: Double = 1.0
    var scrollVolume: Double = 1.0

    // Themes
    var themeID: String = "tactile"
    var samplePackID: String?
    var mouseThemeID: String = Theme.mouseClick.id
    var scrollThemeID: String = Theme.scrollDefaultID

    // Advanced overrides
    var keyboardAdvancedEnabled: Bool = false
    var mouseAdvancedEnabled: Bool = false
    var scrollAdvancedEnabled: Bool = false
    var advanced: AdvancedConfig = AdvancedConfig()

    // Sleep triggers
    var triggers: TriggersConfig = TriggersConfig()

    // Visualizers
    var keyVizEnabled: Bool = false
    var keyVizStyle: KeyVizStyle = .full
    var wpmVizEnabled: Bool = false

    // Spatial audio
    var spatial: SpatialConfig = SpatialConfig()

    // Stats collection (opt-in; default off)
    var statsEnabled: Bool = false

    // Piano Mode — replaces the keyboard click with tuned piano notes.
    var pianoModeEnabled: Bool = false
    var piano: PianoConfig = PianoConfig()
}

@MainActor
enum ProfileStore {
    static let directory: URL = {
        let dir = Paths.appSupport.appendingPathComponent("Profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let activeKey = "activeProfileID"

    static func all() -> [Profile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(Profile.self, from: $0) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    static func save(_ profile: Profile) {
        let url = directory.appendingPathComponent("\(profile.id).json")
        if let data = try? JSONEncoder().encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func delete(_ id: String) {
        let url = directory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    static var activeID: String? {
        get { UserDefaults.standard.string(forKey: activeKey) }
        set { UserDefaults.standard.set(newValue, forKey: activeKey) }
    }

    static func newID() -> String { UUID().uuidString }
}
