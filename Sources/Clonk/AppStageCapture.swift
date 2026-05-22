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
    // Overlay states rendered as a small floating widget (not the popover).
    private static let overlayStates: Set<String> = ["wpm", "keyboard", "piano", "minimal"]

    static func run(state: String, model: AppModel) {
        NSApp.setActivationPolicy(.accessory)
        seed(model, for: state)

        let root: AnyView
        if overlayStates.contains(state) {
            // Dark mode: overlays are always dark-styled floating panels.
            NSApp.appearance = NSAppearance(named: .darkAqua)
            root = AnyView(CaptureOverlay(model: model, state: state))
        } else {
            // Popover: force light for consistent shots.
            NSApp.appearance = NSAppearance(named: .aqua)
            let tab: PopoverTab
            switch state {
            case "settings":  tab = .settings
            case "profiles":  tab = .profiles
            case "triggers":  tab = .triggers
            default:          tab = .sounds
            }
            root = AnyView(CapturePanel(model: model, tab: tab))
        }

        let host = NSHostingController(rootView: root)
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
        window.level = .floating
        window.contentViewController = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            host.view.layoutSubtreeIfNeeded()
            let fit = host.view.fittingSize
            if fit.width > 50 && fit.height > 50 {
                window.setContentSize(fit)
                window.center()
            }
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
        switch state {
        case "sounds":
            model.keyboardAdvancedEnabled = true
            model.mouseAdvancedEnabled = true
            model.scrollAdvancedEnabled = true
        case "wpm":
            model.seedOverlayState(wpm: 85)
        case "keyboard":
            model.keyVizStyle = .full
            model.seedOverlayState(wpm: 0, pressedKeycodes: [38, 40, 37])
        case "piano":
            model.pianoModeEnabled = true
            model.seedOverlayState(wpm: 0, pressedKeycodes: [0, 2, 4, 7, 9])
        case "minimal":
            model.keyVizStyle = .minimal
            model.seedOverlayState(wpm: 0, pressedKeycodes: [31, 34, 32])
        default: break
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

// The overlay widget (WPM, key viz, piano) rendered standalone with
// transparent surround so the capture follows the widget's own shape.
private struct CaptureOverlay: View {
    let model: AppModel
    let state: String

    var body: some View {
        Group {
            switch state {
            case "wpm":
                WPMVisualizerView(model: model)
                    .padding(16)
            case "piano":
                KeyVisualizerView(model: model)
                    .padding(16)
            case "minimal":
                KeyVisualizerView(model: model)
                    .padding(24)
            default: // "keyboard"
                KeyVisualizerView(model: model)
                    .padding(12)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
