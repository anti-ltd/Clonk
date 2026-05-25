import ApplicationServices
import CoreGraphics

// Global keyboard + mouse listener built on a CGEventTap. Listen-only — Clonk
// never modifies or swallows events, it just hears them. Requires the
// Accessibility permission (System Settings › Privacy & Security).
@MainActor
final class KeyMonitor {
    var onKey: ((_ down: Bool, _ bigKey: Bool, _ modifier: Bool, _ keycode: Int) -> Void)?
    var onKeyRepeat: ((_ keycode: Int) -> Void)?
    var onMouse: ((_ down: Bool, _ button: Int) -> Void)?
    var onScroll: ((_ dx: Double, _ dy: Double) -> Void)?
    private(set) var isRunning = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    // Wide keycaps — these get a deeper, slightly louder voice.
    static let bigKeycodes: Set<Int> = [49, 36, 76, 51, 48, 56, 60, 57]

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        // kAXTrustedCheckOptionPrompt — its literal value, used directly to
        // avoid referencing a non-concurrency-safe global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .scrollWheel,
        ]
        let mask: CGEventMask = types.reduce(0) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: clonkEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = src
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
    }

    fileprivate func dispatchKey(down: Bool, autorepeat: Bool, keycode: Int64, modifier: Bool) {
        let code = Int(keycode)
        if autorepeat {
            // Don't fire a sound for repeat events, but surface them so
            // listeners can keep "held key" state alive.
            onKeyRepeat?(code)
            return
        }
        onKey?(down, Self.bigKeycodes.contains(code), modifier, code)
    }

    fileprivate func dispatchMouse(down: Bool, button: Int) {
        onMouse?(down, button)
    }

    fileprivate func dispatchScroll(dx: Double, dy: Double) {
        onScroll?(dx, dy)
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

// C callback. Runs on the main run loop, so it hops onto the main actor.
// Event fields are decoded here (a nonisolated context) so only Sendable
// primitives cross the isolation boundary — never the CGEvent itself.
private func clonkEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .keyDown:
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        MainActor.assumeIsolated { monitor.dispatchKey(down: true, autorepeat: repeated, keycode: code, modifier: false) }
    case .keyUp:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        MainActor.assumeIsolated { monitor.dispatchKey(down: false, autorepeat: false, keycode: code, modifier: false) }
    case .flagsChanged:
        // Modifier engage/disengage — emit a press click either way.
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        MainActor.assumeIsolated { monitor.dispatchKey(down: true, autorepeat: false, keycode: code, modifier: true) }
    case .leftMouseDown:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: true, button: 0) }
    case .rightMouseDown:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: true, button: 1) }
    case .otherMouseDown:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: true, button: 2) }
    case .leftMouseUp:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: false, button: 0) }
    case .rightMouseUp:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: false, button: 1) }
    case .otherMouseUp:
        MainActor.assumeIsolated { monitor.dispatchMouse(down: false, button: 2) }
    case .scrollWheel:
        // Axis 1 = vertical, axis 2 = horizontal. Prefer point deltas;
        // fall back to integer line deltas for notched mice.
        var dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        var dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if dx == 0 && dy == 0 {
            dx = event.getDoubleValueField(.scrollWheelEventDeltaAxis2) * 10
            dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * 10
        }
        MainActor.assumeIsolated { monitor.dispatchScroll(dx: dx, dy: dy) }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { monitor.reenable() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
