// Reel showcase — compiled only in `--showcase` builds (CLONK_SHOWCASE).
// See Makefile: `make run SHOWCASE=1`. Never included in production builds.
//
// Opens the "Clonk Reel" window scene. `SettingsWindowView` installs the
// bridge via `.background(ClonkReelWindowOpenerBridge())` (also gated by
// CLONK_SHOWCASE), which captures the SwiftUI `openWindow` action so the
// menu-bar item can drive it from AppKit.

#if CLONK_SHOWCASE

import AppKit
import SwiftUI

@MainActor
public enum ClonkReelWindowOpener {
    public static var action: OpenWindowAction?
    public static func open() {
        guard let action else { NSSound.beep(); return }
        action(id: "clonk-reel")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let id = window.identifier?.rawValue, id.contains("clonk-reel") else { continue }
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

struct ClonkReelWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { ClonkReelWindowOpener.action = openWindow }
    }
}

#endif
