import AppKit
import SwiftUI

// A scratch text area for trying out Clonk's sounds. Keystrokes here are
// captured as first-responder events, so it works even before the global
// Accessibility permission is granted.
struct SoundPlayground: View {
    let model: AppModel
    var height: CGFloat = 90

    var body: some View {
        SoundTextView(model: model)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}

private struct SoundTextView: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        let textView = ClickTextView()
        textView.model = model
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = "Type here to hear your sounds…"
        textView.autoresizingMask = [.width]

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

// NSTextView that reports raw key and mouse events to the AppModel.
//
// The global event tap already hears these keystrokes once it is running, so
// the playground only emits sound itself when the tap is NOT running (i.e.
// before Accessibility is granted) — otherwise every key would double up.
private final class ClickTextView: NSTextView {
    weak var model: AppModel?
    private var clearedPlaceholder = false

    private var shouldEmit: Bool { model?.monitorRunning == false }

    override func keyDown(with event: NSEvent) {
        clearPlaceholderIfNeeded()
        if !event.isARepeat, shouldEmit {
            model?.playKeyEvent(down: true, bigKey: isBig(event), modifier: false, keycode: Int(event.keyCode))
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if shouldEmit {
            model?.playKeyEvent(down: false, bigKey: isBig(event), modifier: false, keycode: Int(event.keyCode))
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if shouldEmit {
            model?.playKeyEvent(down: true, bigKey: isBig(event), modifier: true, keycode: Int(event.keyCode))
        }
        super.flagsChanged(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if shouldEmit { model?.playMouseEvent(down: true, button: 0) }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if shouldEmit { model?.playMouseEvent(down: false, button: 0) }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if shouldEmit {
            model?.handleScroll(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }
        super.scrollWheel(with: event)
    }

    private func isBig(_ event: NSEvent) -> Bool {
        KeyMonitor.bigKeycodes.contains(Int(event.keyCode))
    }

    private func clearPlaceholderIfNeeded() {
        guard !clearedPlaceholder else { return }
        clearedPlaceholder = true
        string = ""
    }
}
