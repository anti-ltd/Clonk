import SwiftUI

// Clonk — a mechanical keyboard sound simulator for macOS.
//
// Structure:
//   • MenuBarExtra   — a popover holding the entire UI (PopoverView). No
//                      other windows; this is an LSUIElement app.
//   • AppModel       — owns the sound engine, the global key listener, and
//                      every user setting.
//
// Dev tool: `--icon <dir>` renders the AppIcon.iconset folder, then exits.
@main
struct ClonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.model)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--icon"), idx + 1 < args.count {
            AppIconRenderer.run(directory: args[idx + 1])
            NSApp.terminate(nil)
            return
        }

        model.start()
    }
}
