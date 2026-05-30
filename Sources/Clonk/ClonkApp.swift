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

        #if CLONK_SHOWCASE
        // Showcases — only in `--showcase` builds. See Sources/ClonkCore/Showcase.
        Window("Clonk Reel", id: "clonk-reel") {
            ReelSceneView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Sound Check", id: "clonk-soundcheck") {
            SoundCheckView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Switch Tier-List", id: "clonk-tierlist") {
            TierListView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Feature Flex", id: "clonk-featureflex") {
            FeatureFlexView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Oddly Satisfying", id: "clonk-loop") {
            SatisfyingLoopView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Piano Mode", id: "clonk-piano") {
            PianoModeView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Guitar Mode", id: "clonk-guitar") {
            GuitarModeView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)

        Window("Piano × Guitar", id: "clonk-duet") {
            DuetView()
                .onAppear  { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 360, height: 722)
        .windowResizability(.contentSize)
        #endif

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
        #if CLONK_SHOWCASE
        let idsToClose = [ClonkModule.windowID, "clonk-reel", "clonk-soundcheck",
                          "clonk-tierlist", "clonk-featureflex", "clonk-loop",
                          "clonk-piano", "clonk-guitar", "clonk-duet"]
        #else
        let idsToClose = [ClonkModule.windowID]
        #endif
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let id = window.identifier?.rawValue else { continue }
                if idsToClose.contains(where: { id.contains($0) }) { window.close() }
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
        #if CLONK_SHOWCASE
        // Showcases — only in `--showcase` builds.
        menu.addItem(NSMenuItem(
            title: "Reel Showcase", action: #selector(menuReel), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Sound Check", action: #selector(menuSoundCheck), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Switch Tier-List", action: #selector(menuTierList), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "list.number", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Feature Flex", action: #selector(menuFeatureFlex), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Oddly Satisfying", action: #selector(menuLoop), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Piano Mode", action: #selector(menuPiano), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "pianokeys", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Guitar Mode", action: #selector(menuGuitar), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "guitars.fill", accessibilityDescription: nil)
        })
        menu.addItem(NSMenuItem(
            title: "Piano × Guitar", action: #selector(menuDuet), keyEquivalent: ""
        ).then {
            $0.target = self
            $0.image = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)
        })
        #endif
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

    #if CLONK_SHOWCASE
    @objc private func menuReel() {
        ShowcaseWindows.open("clonk-reel")
    }

    @objc private func menuSoundCheck() {
        ShowcaseWindows.open("clonk-soundcheck")
    }

    @objc private func menuTierList() {
        ShowcaseWindows.open("clonk-tierlist")
    }

    @objc private func menuFeatureFlex() {
        ShowcaseWindows.open("clonk-featureflex")
    }

    @objc private func menuLoop() {
        ShowcaseWindows.open("clonk-loop")
    }

    @objc private func menuPiano() {
        ShowcaseWindows.open("clonk-piano")
    }

    @objc private func menuGuitar() {
        ShowcaseWindows.open("clonk-guitar")
    }

    @objc private func menuDuet() {
        ShowcaseWindows.open("clonk-duet")
    }
    #endif

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
