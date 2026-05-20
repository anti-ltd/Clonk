import AppKit
import SwiftUI

// A floating, borderless, draggable panel for visualizer overlays. Stays
// above other windows, joins every Space, doesn't show in the Dock or
// Cmd-Tab. Position is persisted per-name in UserDefaults.
@MainActor
final class OverlayWindow<Content: View>: NSPanel {
    private let storageKey: String

    init(name: String, size: NSSize, defaultRect: NSRect? = nil, @ViewBuilder content: () -> Content) {
        storageKey = "overlay.\(name).frame"
        let saved = UserDefaults.standard.string(forKey: storageKey).flatMap { NSRectFromString($0) }
        let fallback = defaultRect ?? NSRect(x: 100, y: 100, width: size.width, height: size.height)
        let rect = saved ?? fallback
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isOpaque = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView()
        contentView?.addSubview(host)
        if let cv = contentView {
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                host.topAnchor.constraint(equalTo: cv.topAnchor),
                host.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
    }

    func persist() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: storageKey)
    }
}
