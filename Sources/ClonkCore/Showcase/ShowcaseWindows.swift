// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// One captured `OpenWindowAction` drives every showcase window (reel, sound
// check, …) by scene id, so adding a showcase needs no new opener plumbing.
// `SettingsWindowView` installs the bridge via `.background(...)`, also gated
// by CLONK_SHOWCASE — AppKit menu actions can't reach the SwiftUI environment,
// so we stash the action into a @MainActor static at render time.

#if CLONK_SHOWCASE

import AppKit
import SwiftUI

@MainActor
public enum ShowcaseWindows {
    public static var action: OpenWindowAction?

    /// Open a showcase window by its scene id and bring it forward. The async
    /// `makeKeyAndOrderFront` mirrors the settings window: `openWindow` shows
    /// the window but not key when invoked from an NSMenu action.
    public static func open(_ id: String) {
        guard let action else { NSSound.beep(); return }
        action(id: id)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let raw = window.identifier?.rawValue, raw.contains(id) else { continue }
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

struct ShowcaseWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { ShowcaseWindows.action = openWindow }
    }
}

#endif
