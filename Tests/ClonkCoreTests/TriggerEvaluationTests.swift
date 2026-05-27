import Foundation
import Testing

@testable import ClonkCore

// The sleep-rule predicate is pure: given a Snapshot of the world, it
// returns whether a TriggerKind currently fires. These tests pin its
// boundary behaviour so refactors don't quietly flip a rule.
@Suite("Trigger evaluation")
struct TriggerEvaluationTests {

    private func snapshot(
        frontBundle: String? = nil,
        externalKB: Bool = false,
        calendarBusy: Bool = false,
        onBattery: Bool = false,
        batteryPercent: Int = -1,
        idleSeconds: Double = 0,
        nowMinute: Int = 12 * 60,
        weekday: Int = 4,  // Wednesday
        screenCount: Int = 1
    ) -> TriggersManager.Snapshot {
        TriggersManager.Snapshot(
            frontBundle: frontBundle,
            externalKB: externalKB,
            calendarBusy: calendarBusy,
            onBattery: onBattery,
            batteryPercent: batteryPercent,
            idleSeconds: idleSeconds,
            nowMinute: nowMinute,
            weekday: weekday,
            screenCount: screenCount
        )
    }

    // MARK: - Simple boolean kinds

    @Test
    func externalKeyboardReflectsSnapshot() {
        #expect(TriggersManager.evaluate(.externalKeyboard, snapshot(externalKB: true)))
        #expect(!TriggersManager.evaluate(.externalKeyboard, snapshot(externalKB: false)))
    }

    @Test
    func onBatteryReflectsSnapshot() {
        #expect(TriggersManager.evaluate(.onBattery, snapshot(onBattery: true)))
        #expect(!TriggersManager.evaluate(.onBattery, snapshot(onBattery: false)))
    }

    @Test
    func multipleDisplaysNeedsMoreThanOne() {
        #expect(!TriggersManager.evaluate(.multipleDisplays, snapshot(screenCount: 1)))
        #expect(TriggersManager.evaluate(.multipleDisplays, snapshot(screenCount: 2)))
    }

    // MARK: - Low battery

    @Test
    func lowBatteryGateRequiresKnownPercent() {
        // Unknown battery (percent == -1, e.g. desktop Macs) never fires.
        #expect(!TriggersManager.evaluate(.lowBattery(percent: 50), snapshot(batteryPercent: -1)))
        // Above threshold: no.
        #expect(!TriggersManager.evaluate(.lowBattery(percent: 20), snapshot(batteryPercent: 25)))
        // Strictly below: yes.
        #expect(TriggersManager.evaluate(.lowBattery(percent: 20), snapshot(batteryPercent: 19)))
        // Exactly at threshold: no (strict <).
        #expect(!TriggersManager.evaluate(.lowBattery(percent: 20), snapshot(batteryPercent: 20)))
    }

    // MARK: - Idle

    @Test
    func idleFiresAtOrBeyondThreshold() {
        let kind = TriggerKind.idle(seconds: 60)
        #expect(!TriggersManager.evaluate(kind, snapshot(idleSeconds: 59)))
        #expect(TriggersManager.evaluate(kind, snapshot(idleSeconds: 60)))
        #expect(TriggersManager.evaluate(kind, snapshot(idleSeconds: 600)))
    }

    // MARK: - App focus

    @Test
    func appFocusMatchesFrontBundle() {
        let kind = TriggerKind.appFocus(bundleIDs: ["com.apple.Safari", "com.zoom.xos"])
        #expect(TriggersManager.evaluate(kind, snapshot(frontBundle: "com.apple.Safari")))
        #expect(TriggersManager.evaluate(kind, snapshot(frontBundle: "com.zoom.xos")))
        #expect(!TriggersManager.evaluate(kind, snapshot(frontBundle: "com.apple.Terminal")))
        #expect(!TriggersManager.evaluate(kind, snapshot(frontBundle: nil)))
    }

    // MARK: - Schedule (windowed time)

    @Test
    func scheduleSameStartAndEndNeverFires() {
        let kind = TriggerKind.schedule(startMinute: 9 * 60, endMinute: 9 * 60, weekdays: [])
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 9 * 60)))
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 13 * 60)))
    }

    @Test
    func scheduleDaytimeWindowIncludesStartExcludesEnd() {
        // 09:00–17:00 — start inclusive, end exclusive.
        let kind = TriggerKind.schedule(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [])
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 8 * 60 + 59)))
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 9 * 60)))
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 12 * 60)))
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 16 * 60 + 59)))
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 17 * 60)))
    }

    @Test
    func scheduleOvernightWindowWraps() {
        // 22:00–06:00 — covers late evening and early morning.
        let kind = TriggerKind.schedule(startMinute: 22 * 60, endMinute: 6 * 60, weekdays: [])
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 23 * 60)))
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 2 * 60)))
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 22 * 60)))
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 6 * 60)))
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 12 * 60)))
    }

    @Test
    func scheduleEmptyWeekdaysMatchesEveryDay() {
        let kind = TriggerKind.schedule(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [])
        for day in 1...7 {
            #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 10 * 60, weekday: day)))
        }
    }

    @Test
    func scheduleSpecificWeekdaysGate() {
        // Weekdays only: Mon..Fri = 2..6 (Calendar convention 1=Sun).
        let kind = TriggerKind.schedule(startMinute: 9 * 60, endMinute: 17 * 60,
                                        weekdays: [2, 3, 4, 5, 6])
        // Sunday (1) and Saturday (7) excluded.
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 10 * 60, weekday: 1)))
        #expect(!TriggersManager.evaluate(kind, snapshot(nowMinute: 10 * 60, weekday: 7)))
        // Wednesday (4) included.
        #expect(TriggersManager.evaluate(kind, snapshot(nowMinute: 10 * 60, weekday: 4)))
    }
}
