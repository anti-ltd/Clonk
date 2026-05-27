import AppKit
import SwiftUI
import iUX_MacOS
import ClonkCore

// Clonk — a mechanical keyboard sound simulator for macOS.
//
// Structure:
//   • MenuBarController — iUX-MacOS's menu bar host. Left-click opens the
//                         everyday menu (Settings / Quit); right-click opens
//                         the settings popover with its pop-out button.
//   • AppModel          — owns the sound engine, the global key listener, and
//                         every user setting.
//
// Dev tool: `--icon <dir>` renders the AppIcon.iconset folder, then exits.
@main
struct ClonkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The full settings window. A SwiftUI `Window` scene (rather than a
        // hand-built `NSWindow`) gives `NavigationSplitView` the unified
        // toolbar, transparent titlebar, and vibrant sidebar that match every
        // other iUX-MacOS app. Opened via `@Environment(\.openWindow)`.
        Window("Clonk", id: ClonkModule.windowID) {
            appDelegate.clonk.windowView()
                // The app is LSUIElement (.accessory) so it never appears in
                // the Dock or Cmd-Tab. While the settings window is up we
                // promote to .regular so it activates and accepts clicks;
                // dropping back to .accessory on close hides the Dock tile.
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 740, height: 580)
        .windowToolbarStyle(.unified)

        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clonk = ClonkModule()
    private var menuBar: MenuBarController?

    // Clonk is LSUIElement — the menu-bar item is the whole app. The pop-out
    // settings window is a transient surface; closing it must not terminate the
    // process. Without this, AppKit's default returns true the moment a real
    // window closes and the menu bar item disappears.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

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

        // Click semantics match FileMaster: left-click is the everyday menu
        // (Settings, Quit), right-click is the settings popover. `Settings`
        // opens the pop-out window directly — the popover is for the quick-
        // glance right-click surface.
        menuBar = MenuBarController(
            symbolName: ClonkModule.symbolName,
            accessibilityLabel: ClonkModule.displayName,
            popoverSize: NSSize(width: 460, height: 560),
            rootView: clonk.settingsView(),
            clickStyle: .leftClickMenu,
            menuProvider: { [weak self] in self?.contextMenu() }
        )
        clonk.start()

        // SwiftUI's `Window(id:)` scene auto-opens at launch. Clonk is
        // LSUIElement — the pop-out settings window is opened on demand via
        // the popover's macwindow button. Close just that window if SwiftUI
        // brought it up, matched by `NSWindow.identifier` (SwiftUI sets it
        // from the scene id). A blanket close would also kill the status
        // item's backing window and the menu bar would stop responding.
        let targetID = ClonkModule.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let id = window.identifier?.rawValue, id.contains(targetID) else { continue }
                window.close()
            }
        }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Settings", action: #selector(menuSettings), keyEquivalent: ","
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(menuQuit), keyEquivalent: "q"
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        })
        return menu
    }

    @objc private func menuSettings() {
        ClonkWindowOpener.open()
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
