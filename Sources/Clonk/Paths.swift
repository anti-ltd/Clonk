import Foundation

// On-disk home for everything Clonk persists. Every counter-ltd app keeps its
// files together under a single org-scoped root so they're easy to find, back
// up, and remove:
//
//   ~/Library/Application Support/counter-ltd/clonk/
//
// All file storage in the app derives from `Paths.appSupport`.
enum Paths {
    // The app's storage root. Created on first access.
    static let appSupport: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("counter-ltd/clonk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
}
