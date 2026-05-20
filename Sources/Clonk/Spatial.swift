import Foundation

// Per-key positions in a normalized "virtual keyboard plane" centered at
// the listener. x in roughly -1…1 across the keyboard width, y small
// vertical lift, z slightly in front (negative).
struct SpatialConfig: Codable, Equatable {
    var enabled: Bool = false

    // Stereo spread of the keyboard. 0 = mono, 1 = full hard-pan width.
    var width: Double = 0.6

    // Listening "distance" — pulls all sources closer/further (loudness +
    // reverb tail). 0…1 mapped to ~0.3…2.0 meters inside the engine.
    var distance: Double = 0.4

    // Whether to apply HRTF (head-related transfer function). Costs CPU
    // but produces real 3D imaging on headphones.
    var hrtf: Bool = true
}
