@preconcurrency import AVFoundation
import Foundation

// User-imported sound packs. Clonk ships none — a pack is just a folder of
// audio files the user drops in. On each keypress a random file is played.
struct SamplePack: Identifiable, Equatable {
    let id: String          // folder name
    let name: String
    let url: URL
    let fileCount: Int

    static func == (a: SamplePack, b: SamplePack) -> Bool { a.id == b.id }
}

enum SamplePackStore {
    static let audioExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a", "flac"]

    static var packsDirectory: URL {
        let dir = Paths.appSupport.appendingPathComponent("SamplePacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func installed() -> [SamplePack] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: packsDirectory,
                                                        includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.compactMap { url -> SamplePack? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let files = audioFiles(in: url)
            guard !files.isEmpty else { return nil }
            return SamplePack(id: url.lastPathComponent, name: url.lastPathComponent,
                              url: url, fileCount: files.count)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func audioFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
    }

    // Copy a chosen folder into the store. Returns the installed pack.
    static func importFolder(_ source: URL) throws -> SamplePack {
        let fm = FileManager.default
        let dest = packsDirectory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for file in audioFiles(in: source) {
            try fm.copyItem(at: file, to: dest.appendingPathComponent(file.lastPathComponent))
        }
        let count = audioFiles(in: dest).count
        guard count > 0 else {
            try? fm.removeItem(at: dest)
            throw ClonkError.noAudioFiles
        }
        return SamplePack(id: dest.lastPathComponent, name: dest.lastPathComponent, url: dest, fileCount: count)
    }

    static func delete(_ pack: SamplePack) {
        try? FileManager.default.removeItem(at: pack.url)
    }
}

enum ClonkError: LocalizedError {
    case noAudioFiles
    var errorDescription: String? {
        switch self {
        case .noAudioFiles: return "That folder has no supported audio files (wav, aiff/aif, caf, mp3, m4a, flac)."
        }
    }
}

// Sample files decoded and resampled to Clonk's canonical playback format.
struct SampleBank {
    let buffers: [AVAudioPCMBuffer]
    var isEmpty: Bool { buffers.isEmpty }

    static func load(_ pack: SamplePack, format: AVAudioFormat) -> SampleBank {
        let buffers = SamplePackStore.audioFiles(in: pack.url).compactMap {
            decode($0, to: format)
        }
        return SampleBank(buffers: buffers)
    }

    func randomBuffer() -> AVAudioPCMBuffer? { buffers.randomElement() }

    private static func decode(_ url: URL, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let srcFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frames) else { return nil }
        do { try file.read(into: srcBuffer) } catch { return nil }

        if srcFormat == format { return srcBuffer }
        guard let converter = AVAudioConverter(from: srcFormat, to: format) else { return nil }
        let ratio = format.sampleRate / srcFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity) else { return nil }

        final class Feed: @unchecked Sendable { var done = false }
        let feed = Feed()
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if feed.done { status.pointee = .endOfStream; return nil }
            feed.done = true
            status.pointee = .haveData
            return srcBuffer
        }
        return error == nil ? outBuffer : nil
    }
}
