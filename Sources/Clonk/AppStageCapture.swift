#if APPSTAGE
import AppKit
import SwiftUI

// Dev tool: render one UI state into an on-screen window for appstage to
// screenshot, then keep running so the window can be captured. Mirrors the
// `--icon` pattern. Activated by `--appstage <state>`.
//
// State is isolated via CLONK_STATE_DIR (see Paths), so a capture run never
// touches the user's real profiles. Prints a single line that appstage parses:
//
//   @@APPSTAGE_READY@@ {"window":<cgWindowID>,"w":W,"h":H,"slug":"<state>"}
//
// appstage then runs `screencapture -l<window> -o` and terminates the process.
@MainActor
enum AppStageCapture {
    static func run(state: String, model: AppModel) {
        // Menu-bar style (no Dock icon), forced light for consistent shots.
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)

        seed(model, for: state)

        let tab: PopoverTab = state == "settings" ? .settings : .sounds
        let host = NSHostingController(rootView: CapturePanel(model: model, tab: tab))
        host.view.layoutSubtreeIfNeeded()

        let window = CaptureWindow(
            contentRect: NSRect(origin: .zero, size: host.view.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating // keep above other windows for the capture
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let SwiftUI lay out and paint, then size to content.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            host.view.layoutSubtreeIfNeeded()
            let fit = host.view.fittingSize
            if fit.width > 50 && fit.height > 50 {
                window.setContentSize(fit)
                window.center()
            }
            // Re-assert active/key so controls render in their active (accent)
            // state, not the desaturated inactive state, when captured.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let f = window.frame
                print(
                    "@@APPSTAGE_READY@@ {\"window\":\(window.windowNumber),"
                    + "\"w\":\(Int(f.width)),\"h\":\(Int(f.height)),\"slug\":\"\(state)\"}"
                )
                fflush(stdout)
            }
        }
    }

    // Believable demo state so marketing shots look stocked and consistent.
    private static func seed(_ model: AppModel, for state: String) {
        model.keySoundEnabled = true
        model.releaseSoundEnabled = true
        model.mouseSoundEnabled = true
        model.mouseReleaseEnabled = true
        model.scrollSoundEnabled = true
        model.muteModifiers = false
        model.scrollSensitivity = 0.16
        if state == "sounds" {
            // Show the per-input advanced editors (keyboard grid, etc.).
            model.keyboardAdvancedEnabled = true
            model.mouseAdvancedEnabled = true
            model.scrollAdvancedEnabled = true
        }
    }
}

// Borderless windows can't become key by default; allow it so controls render
// in their active state.
private final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// The popover content as a self-contained rounded panel (no popover arrow).
private struct CapturePanel: View {
    let model: AppModel
    let tab: PopoverTab

    var body: some View {
        PopoverView(model: model, initialTab: tab)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif
