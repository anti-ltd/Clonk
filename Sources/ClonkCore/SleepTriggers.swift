import AppKit
import EventKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps

// Sleep triggers — a user-defined list of rules that mute Clonk
// automatically while any rule is active. Each rule names a `TriggerKind`
// (with its own parameters) plus an `invert` flag, so users can compose
// arbitrary conditions instead of choosing from fixed presets.

struct TriggersConfig: Codable, Equatable {
    var enabled: Bool = false
    var rules: [TriggerRule] = []

    init(enabled: Bool = false, rules: [TriggerRule] = []) {
        self.enabled = enabled
        self.rules = rules
    }

    // Migration: older profiles stored individual preset flags. Decode
    // those into equivalent rules so users don't lose their setup.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        if let r = try? c.decode([TriggerRule].self, forKey: .rules) {
            rules = r
            return
        }
        var migrated: [TriggerRule] = []
        if (try? c.decode(Bool.self, forKey: .externalKeyboard)) == true {
            migrated.append(TriggerRule(name: "External keyboard", kind: .externalKeyboard))
        }
        if (try? c.decode(Bool.self, forKey: .duringCalendarEvents)) == true {
            migrated.append(TriggerRule(name: "Calendar event", kind: .calendarBusy))
        }
        if (try? c.decode(Bool.self, forKey: .schedule)) == true {
            let s = (try? c.decode(Int.self, forKey: .scheduleStartMinute)) ?? 9 * 60
            let e = (try? c.decode(Int.self, forKey: .scheduleEndMinute)) ?? 17 * 60
            migrated.append(TriggerRule(
                name: "Outside work hours", invert: true,
                kind: .schedule(startMinute: s, endMinute: e, weekdays: [])))
        }
        if (try? c.decode(Bool.self, forKey: .appBlocklist)) == true {
            let ids = (try? c.decode([String].self, forKey: .blockedBundleIDs)) ?? []
            migrated.append(TriggerRule(name: "App blocklist", kind: .appFocus(bundleIDs: ids)))
        }
        rules = migrated
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(rules, forKey: .rules)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, rules
        case externalKeyboard, duringCalendarEvents
        case schedule, scheduleStartMinute, scheduleEndMinute
        case appBlocklist, blockedBundleIDs
    }
}

struct TriggerRule: Codable, Equatable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var enabled: Bool = true
    var invert: Bool = false
    var kind: TriggerKind
}

enum TriggerKind: Codable, Equatable, Hashable {
    case externalKeyboard
    case calendarBusy
    case schedule(startMinute: Int, endMinute: Int, weekdays: [Int])
    case appFocus(bundleIDs: [String])
    case onBattery
    case lowBattery(percent: Int)
    case idle(seconds: Int)
    case multipleDisplays

    var typeID: String {
        switch self {
        case .externalKeyboard: return "externalKeyboard"
        case .calendarBusy: return "calendarBusy"
        case .schedule: return "schedule"
        case .appFocus: return "appFocus"
        case .onBattery: return "onBattery"
        case .lowBattery: return "lowBattery"
        case .idle: return "idle"
        case .multipleDisplays: return "multipleDisplays"
        }
    }

    var label: String {
        switch self {
        case .externalKeyboard: return "External keyboard"
        case .calendarBusy: return "Calendar event"
        case .schedule: return "Time of day"
        case .appFocus: return "Front app"
        case .onBattery: return "On battery"
        case .lowBattery: return "Battery low"
        case .idle: return "Idle"
        case .multipleDisplays: return "Multiple displays"
        }
    }

    var symbol: String {
        switch self {
        case .externalKeyboard: return "keyboard"
        case .calendarBusy: return "calendar"
        case .schedule: return "clock"
        case .appFocus: return "app.badge"
        case .onBattery: return "battery.75"
        case .lowBattery: return "battery.25"
        case .idle: return "pause.circle"
        case .multipleDisplays: return "display.2"
        }
    }

    var summary: String {
        switch self {
        case .externalKeyboard: return "when a non-Apple keyboard is connected"
        case .calendarBusy: return "during any Calendar event"
        case let .schedule(s, e, days):
            let dayStr = days.isEmpty ? "every day" : Self.dayList(days)
            return String(format: "between %02d:%02d–%02d:%02d, %@",
                          s / 60, s % 60, e / 60, e % 60, dayStr)
        case let .appFocus(ids):
            if ids.isEmpty { return "when a listed app is in front" }
            return "front app is " + ids.joined(separator: ", ")
        case .onBattery: return "while running on battery"
        case let .lowBattery(p): return "while battery is below \(p)%"
        case let .idle(s):
            if s >= 60 { return "after \(s/60) min of inactivity" }
            return "after \(s)s of inactivity"
        case .multipleDisplays: return "when more than one display is connected"
        }
    }

    static func dayList(_ days: [Int]) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sorted = days.sorted()
        return sorted.compactMap { (1...7).contains($0) ? names[$0 - 1] : nil }.joined(separator: " ")
    }

    static let templates: [TriggerKind] = [
        .externalKeyboard,
        .calendarBusy,
        .schedule(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: []),
        .appFocus(bundleIDs: []),
        .onBattery,
        .lowBattery(percent: 20),
        .idle(seconds: 300),
        .multipleDisplays,
    ]
}

@MainActor
final class TriggersManager {
    private(set) var config: TriggersConfig
    private(set) var isMuted: Bool = false
    private(set) var activeRuleIDs: Set<UUID> = []
    var onChange: () -> Void = {}

    private var pollTimer: Timer?
    private var hidManager: IOHIDManager?
    private var workspaceObserver: NSObjectProtocol?
    private var calendarObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let store = EKEventStore()
    private var calendarAuthorized = false
    private var externalKBConnected: Bool = false
    private var calendarBusyCached: Bool = false

    init(config: TriggersConfig) {
        self.config = config
    }

    func start() { applyEnablement() }

    func update(_ cfg: TriggersConfig) {
        config = cfg
        applyEnablement()
    }

    func isActive(_ rule: TriggerRule) -> Bool { activeRuleIDs.contains(rule.id) }

    private func applyEnablement() {
        teardown()
        guard config.enabled, !config.rules.isEmpty else {
            if isMuted || !activeRuleIDs.isEmpty {
                isMuted = false; activeRuleIDs.removeAll(); onChange()
            }
            return
        }

        let kinds = Set(config.rules.filter(\.enabled).map(\.kind.typeID))

        if kinds.contains("externalKeyboard") { setupHID() }
        if kinds.contains("calendarBusy") { setupCalendar() }
        if kinds.contains("appFocus") { setupWorkspace() }
        if kinds.contains("multipleDisplays") { setupScreens() }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        recompute()
    }

    private func teardown() {
        pollTimer?.invalidate(); pollTimer = nil
        if let m = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        if let o = workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        workspaceObserver = nil
        if let o = calendarObserver { NotificationCenter.default.removeObserver(o) }
        calendarObserver = nil
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
    }

    // MARK: - Observer setup

    private func setupHID() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<TriggersManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshExternalKB(); me.recompute() }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<TriggersManager>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.refreshExternalKB(); me.recompute() }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = m
        refreshExternalKB()
    }

    private func refreshExternalKB() {
        guard let m = hidManager,
              let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else {
            externalKBConnected = false; return
        }
        externalKBConnected = set.contains { device in
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            return vendor != 0x05AC && vendor != 0x004C
        }
    }

    private func setupCalendar() {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] granted, _ in
                Task { @MainActor in
                    self?.calendarAuthorized = granted
                    self?.beginCalendarObserve()
                }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] granted, _ in
                Task { @MainActor in
                    self?.calendarAuthorized = granted
                    self?.beginCalendarObserve()
                }
            }
        }
    }

    private func beginCalendarObserve() {
        guard calendarAuthorized else { return }
        calendarObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCalendar(); self?.recompute() }
        }
        refreshCalendar()
        recompute()
    }

    private func refreshCalendar() {
        guard calendarAuthorized else { calendarBusyCached = false; return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(60),
            calendars: nil)
        calendarBusyCached = store.events(matching: predicate).contains { e in
            e.startDate <= now && e.endDate >= now && !e.isAllDay
        }
    }

    private func setupWorkspace() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
    }

    private func setupScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
    }

    // MARK: - Recompute

    private func recompute() {
        guard config.enabled else {
            if isMuted || !activeRuleIDs.isEmpty {
                isMuted = false; activeRuleIDs.removeAll(); onChange()
            }
            return
        }
        let snap = stateSnapshot()
        var active: Set<UUID> = []
        for rule in config.rules where rule.enabled {
            let raw = evaluate(rule.kind, snap)
            if raw != rule.invert { active.insert(rule.id) }
        }
        let muted = !active.isEmpty
        if muted != isMuted || active != activeRuleIDs {
            isMuted = muted
            activeRuleIDs = active
            onChange()
        }
    }

    // Internal (not private) so the test target can construct synthetic
    // snapshots and exercise `evaluate(_:_:)` without standing up a full
    // observer graph.
    nonisolated struct Snapshot: Sendable {
        let frontBundle: String?
        let externalKB: Bool
        let calendarBusy: Bool
        let onBattery: Bool
        let batteryPercent: Int
        let idleSeconds: Double
        let nowMinute: Int
        let weekday: Int  // 1=Sun..7=Sat (Calendar convention)
        let screenCount: Int
    }

    private func stateSnapshot() -> Snapshot {
        let cal = Calendar.current
        let comp = cal.dateComponents([.hour, .minute, .weekday], from: Date())
        let (onAC, percent) = batterySnapshot()
        return Snapshot(
            frontBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            externalKB: externalKBConnected,
            calendarBusy: calendarBusyCached,
            onBattery: !onAC,
            batteryPercent: percent,
            idleSeconds: systemIdleSeconds(),
            nowMinute: (comp.hour ?? 0) * 60 + (comp.minute ?? 0),
            weekday: comp.weekday ?? 1,
            screenCount: NSScreen.screens.count
        )
    }

    private func evaluate(_ kind: TriggerKind, _ s: Snapshot) -> Bool {
        Self.evaluate(kind, s)
    }

    // Pure predicate, isolated from any system state — same logic used by
    // recompute(), surfaced so tests can hand it canned snapshots.
    nonisolated static func evaluate(_ kind: TriggerKind, _ s: Snapshot) -> Bool {
        switch kind {
        case .externalKeyboard: return s.externalKB
        case .calendarBusy: return s.calendarBusy
        case let .schedule(start, end, days):
            if !days.isEmpty && !days.contains(s.weekday) { return false }
            if start == end { return false }
            if start < end { return s.nowMinute >= start && s.nowMinute < end }
            return s.nowMinute >= start || s.nowMinute < end
        case let .appFocus(ids):
            guard let front = s.frontBundle else { return false }
            return ids.contains(front)
        case .onBattery: return s.onBattery
        case let .lowBattery(p): return s.batteryPercent >= 0 && s.batteryPercent < p
        case let .idle(secs): return s.idleSeconds >= Double(secs)
        case .multipleDisplays: return s.screenCount > 1
        }
    }
}

// MARK: - System helpers

private func batterySnapshot() -> (onAC: Bool, percent: Int) {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
    else { return (true, -1) }
    for src in sources {
        guard let info = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any]
        else { continue }
        let state = info[kIOPSPowerSourceStateKey] as? String
        let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? -1
        let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
        let onAC = (state == kIOPSACPowerValue)
        let pct = capacity >= 0 && max > 0 ? Int((Double(capacity) / Double(max)) * 100.0) : -1
        return (onAC, pct)
    }
    return (true, -1)
}

private func systemIdleSeconds() -> Double {
    let any = CGEventType(rawValue: ~0)!
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
}
