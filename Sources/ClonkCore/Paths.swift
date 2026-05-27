import Foundation

// On-disk home for everything Clonk persists. Every Anti Limited app keeps
// its files together under a single org-scoped root so they're easy to find,
// back up, and remove:
//
//   ~/Library/Application Support/anti-ltd/clonk/
//
// All file storage in the app derives from `Paths.appSupport`.
enum Paths {
#if APPSTAGE
    // Capture-only build (appstage screenshots). Storage is forced to a
    // throwaway directory so a capture run can never read or write the user's
    // real profiles. This whole branch is compiled out of normal/release builds.
    static let appSupport: URL = {
        let fm = FileManager.default
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["CLONK_STATE_DIR"],
           !override.isEmpty {
            dir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("clonk-appstage", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
#else
    // The app's storage root. Created on first access.
    static let appSupport: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("anti-ltd/clonk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
#endif
}
