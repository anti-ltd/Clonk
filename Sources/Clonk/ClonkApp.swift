import AppKit
import SwiftUI
import iUX
import ClonkCore

// Clonk — a mechanical keyboard sound simulator for macOS.
//
// Structure:
//   • MenuBarController — iUX's menu bar host. Left-click toggles the popover;
//                         right-click opens a small AppKit menu (Quit, etc.).
//   • AppModel          — owns the sound engine, the global key listener, and
//                         every user setting.
//
// Dev tool: `--icon <dir>` renders the AppIcon.iconset folder, then exits.
@main
struct ClonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clonk = ClonkModule()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--icon"), idx + 1 < args.count {
            AppIconRenderer.run(directory: args[idx + 1])
            NSApp.terminate(nil)
            return
        }

        // appstage screenshot mode: render one UI state on-screen and wait to be
        // captured. Skips the status item and the live key/sound engine. Compiled
        // in only for appstage capture builds (-DAPPSTAGE); absent from releases.
        #if APPSTAGE
        if let idx = args.firstIndex(of: "--appstage"), idx + 1 < args.count {
            clonk.runAppStage(state: args[idx + 1])
            return
        }
        #endif

        menuBar = MenuBarController(
            symbolName: ClonkModule.symbolName,
            accessibilityLabel: ClonkModule.displayName,
            popoverSize: NSSize(width: 460, height: 560),
            rootView: clonk.settingsView(),
            menuProvider: { [weak self] in self?.contextMenu() }
        )
        clonk.start()
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let muteTitle = clonk.isMuted ? "Sleeping (auto)" : "Active"
        let status = NSMenuItem(title: muteTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Open Clonk", action: #selector(menuOpen), keyEquivalent: ""
        ).then { $0.target = self })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Clonk", action: #selector(menuQuit), keyEquivalent: "q"
        ).then { $0.target = self })
        return menu
    }

    @objc private func menuOpen() {
        menuBar?.toggle()
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }
}

// Tiny helper so menu-item builders stay one line each.
private extension NSObject {
    func then(_ apply: (Self) -> Void) -> Self {
        apply(self)
        return self
    }
}
