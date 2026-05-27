import Foundation

// A Profile is a named snapshot of every Clonk setting. Users can keep
// several (e.g. "Loud at home", "Quiet in cafe", "Streaming") and switch
// instantly. The active profile ID is remembered across launches.
//
// Storage: one JSON file per profile under
//   ~/Library/Application Support/anti-ltd/clonk/Profiles/<id>.json
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
    var cpmVizEnabled: Bool = false

    // Spatial audio
    var spatial: SpatialConfig = SpatialConfig()

    // Stats collection (opt-in; default off)
    var statsEnabled: Bool = false

    // Piano Mode — replaces the keyboard click with tuned piano notes.
    var pianoModeEnabled: Bool = false
    var piano: PianoConfig = PianoConfig()

    // Guitar Mode — replaces the keyboard click with plucked guitar strings.
    var guitarModeEnabled: Bool = false
    var guitar: GuitarConfig = GuitarConfig()

    // Audio backend choice. Cached uses a pool of AVAudioPlayers loaded
    // with pre-rendered click variants — no always-running audio graph, so
    // idle is genuinely 0%. Live uses AVAudioEngine, which is required for
    // piano / guitar synthesis and spatial audio (the model auto-promotes
    // when those are on, regardless of this setting).
    var enginePlaybackMode: EnginePlaybackMode = .cached

    // Release-click suppression threshold (seconds). When the EMA of inter-
    // press intervals is below this, the key-up click is skipped — at fast
    // typing rates the release sound piles on top of the next press and
    // doubles audio-engine load without being audible as a distinct click.
    // 0 = never suppress; the practical range is 0…0.25 s.
    var releaseSuppressInterval: Double = 0.085

    // Custom decoder: tolerate older profiles missing newer fields by
    // falling back to the property's default. Without this, adding a new
    // setting silently breaks every saved profile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        keySoundEnabled = (try? c.decode(Bool.self, forKey: .keySoundEnabled)) ?? true
        mouseSoundEnabled = (try? c.decode(Bool.self, forKey: .mouseSoundEnabled)) ?? true
        releaseSoundEnabled = (try? c.decode(Bool.self, forKey: .releaseSoundEnabled)) ?? true
        mouseReleaseEnabled = (try? c.decode(Bool.self, forKey: .mouseReleaseEnabled)) ?? true
        muteModifiers = (try? c.decode(Bool.self, forKey: .muteModifiers)) ?? false
        scrollSoundEnabled = (try? c.decode(Bool.self, forKey: .scrollSoundEnabled)) ?? true
        scrollSensitivity = (try? c.decode(Double.self, forKey: .scrollSensitivity)) ?? 0.35
        volume = (try? c.decode(Double.self, forKey: .volume)) ?? 0.7
        keyVolume = (try? c.decode(Double.self, forKey: .keyVolume)) ?? 1.0
        mouseVolume = (try? c.decode(Double.self, forKey: .mouseVolume)) ?? 1.0
        scrollVolume = (try? c.decode(Double.self, forKey: .scrollVolume)) ?? 1.0
        themeID = (try? c.decode(String.self, forKey: .themeID)) ?? "tactile"
        samplePackID = try? c.decodeIfPresent(String.self, forKey: .samplePackID)
        mouseThemeID = (try? c.decode(String.self, forKey: .mouseThemeID)) ?? Theme.mouseClick.id
        scrollThemeID = (try? c.decode(String.self, forKey: .scrollThemeID)) ?? Theme.scrollDefaultID
        keyboardAdvancedEnabled = (try? c.decode(Bool.self, forKey: .keyboardAdvancedEnabled)) ?? false
        mouseAdvancedEnabled = (try? c.decode(Bool.self, forKey: .mouseAdvancedEnabled)) ?? false
        scrollAdvancedEnabled = (try? c.decode(Bool.self, forKey: .scrollAdvancedEnabled)) ?? false
        advanced = (try? c.decode(AdvancedConfig.self, forKey: .advanced)) ?? AdvancedConfig()
        triggers = (try? c.decode(TriggersConfig.self, forKey: .triggers)) ?? TriggersConfig()
        keyVizEnabled = (try? c.decode(Bool.self, forKey: .keyVizEnabled)) ?? false
        keyVizStyle = (try? c.decode(KeyVizStyle.self, forKey: .keyVizStyle)) ?? .full
        wpmVizEnabled = (try? c.decode(Bool.self, forKey: .wpmVizEnabled)) ?? false
        cpmVizEnabled = (try? c.decode(Bool.self, forKey: .cpmVizEnabled)) ?? false
        spatial = (try? c.decode(SpatialConfig.self, forKey: .spatial)) ?? SpatialConfig()
        statsEnabled = (try? c.decode(Bool.self, forKey: .statsEnabled)) ?? false
        pianoModeEnabled = (try? c.decode(Bool.self, forKey: .pianoModeEnabled)) ?? false
        piano = (try? c.decode(PianoConfig.self, forKey: .piano)) ?? PianoConfig()
        guitarModeEnabled = (try? c.decode(Bool.self, forKey: .guitarModeEnabled)) ?? false
        guitar = (try? c.decode(GuitarConfig.self, forKey: .guitar)) ?? GuitarConfig()
        enginePlaybackMode = (try? c.decode(EnginePlaybackMode.self, forKey: .enginePlaybackMode)) ?? .cached
        releaseSuppressInterval = (try? c.decode(Double.self, forKey: .releaseSuppressInterval)) ?? 0.085
    }

    // Default memberwise init (needed because the custom decoder above
    // suppressed Swift's synthesised one).
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

enum EnginePlaybackMode: String, Codable, CaseIterable, Identifiable {
    case cached
    case live
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cached: return "Cached (low CPU)"
        case .live:   return "Live (real-time)"
        }
    }
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
