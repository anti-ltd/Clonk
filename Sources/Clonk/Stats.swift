import Foundation

// Opt-in local-only usage stats. Default: OFF. Nothing ever leaves the
// Mac. Storage is one JSON file in Application Support.
struct StatsSnapshot: Codable, Equatable {
    var totalKeys: Int = 0
    var totalMouse: Int = 0
    var totalScrolls: Int = 0
    var peakWPM: Double = 0

    // Keycode → count. Drives the heatmap.
    var keyCounts: [Int: Int] = [:]

    // Daily rolling counts, keyed by ISO "yyyy-MM-dd". Trimmed to 30 days.
    var daily: [String: Int] = [:]
}

@MainActor
final class StatsRecorder {
    private(set) var snapshot: StatsSnapshot
    private let url: URL
    private var saveTimer: Timer?

    private static let fileURL = Paths.appSupport.appendingPathComponent("stats.json")

    init() {
        url = Self.fileURL
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(StatsSnapshot.self, from: data) {
            snapshot = s
        } else {
            snapshot = StatsSnapshot()
        }
    }

    func recordKey(_ keycode: Int) {
        snapshot.totalKeys += 1
        snapshot.keyCounts[keycode, default: 0] += 1
        bumpDaily()
        scheduleSave()
    }

    func recordMouse() {
        snapshot.totalMouse += 1
        scheduleSave()
    }

    func recordScroll() {
        snapshot.totalScrolls += 1
        scheduleSave()
    }

    func recordWPM(_ wpm: Double) {
        guard wpm > snapshot.peakWPM else { return }
        snapshot.peakWPM = wpm
        scheduleSave()
    }

    func reset() {
        snapshot = StatsSnapshot()
        save()
    }

    func exportCSV() -> String {
        var lines = ["metric,value"]
        lines.append("totalKeys,\(snapshot.totalKeys)")
        lines.append("totalMouse,\(snapshot.totalMouse)")
        lines.append("totalScrolls,\(snapshot.totalScrolls)")
        lines.append("peakWPM,\(snapshot.peakWPM)")
        lines.append("")
        lines.append("date,keys")
        for (day, count) in snapshot.daily.sorted(by: { $0.key < $1.key }) {
            lines.append("\(day),\(count)")
        }
        lines.append("")
        lines.append("keycode,count")
        for (code, count) in snapshot.keyCounts.sorted(by: { $0.value > $1.value }) {
            lines.append("\(code),\(count)")
        }
        return lines.joined(separator: "\n")
    }

    private func bumpDaily() {
        let key = Self.todayKey()
        snapshot.daily[key, default: 0] += 1
        // Trim to 30 days.
        if snapshot.daily.count > 60 {
            let sorted = snapshot.daily.keys.sorted()
            let toDrop = sorted.prefix(sorted.count - 30)
            for k in toDrop { snapshot.daily.removeValue(forKey: k) }
        }
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // Coalesced save — batch writes so we never hit the disk per keystroke.
    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    private func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// Rolling WPM estimator. A "word" = 5 characters (industry convention).
@MainActor
final class WPMMeter {
    private var charTimestamps: [Date] = []
    private let window: TimeInterval = 5.0

    var current: Double {
        let now = Date()
        let cutoff = now.addingTimeInterval(-window)
        let recent = charTimestamps.filter { $0 >= cutoff }.count
        // Scale 5s window → minute.
        return Double(recent) / 5.0 * 60.0 / 5.0
    }

    func recordChar() {
        let now = Date()
        charTimestamps.append(now)
        // Trim periodically.
        if charTimestamps.count > 256 {
            let cutoff = now.addingTimeInterval(-window)
            charTimestamps.removeAll { $0 < cutoff }
        }
    }

    func reset() { charTimestamps.removeAll() }
}
