import AppKit
import SwiftUI

// Clonk — a mechanical keyboard sound simulator for macOS.
//
// Structure:
//   • NSStatusItem   — menu bar icon. Left-click toggles the popover; right-
//                      click opens a small AppKit menu (Quit, etc.).
//   • AppModel       — owns the sound engine, the global key listener, and
//                      every user setting.
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
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--icon"), idx + 1 < args.count {
            AppIconRenderer.run(directory: args[idx + 1])
            NSApp.terminate(nil)
            return
        }

        installStatusItem()
        model.start()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Clonk")
            button.target = self
            button.action = #selector(handleStatusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 460, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model)
        )
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp ||
            (event?.modifierFlags.contains(.control) ?? false)
        if isRight {
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let muteTitle = model.isMuted ? "Sleeping (auto)" : "Active"
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

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuOpen() {
        guard let button = statusItem?.button else { return }
        togglePopover(from: button)
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
