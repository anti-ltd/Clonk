import AppKit
import SwiftUI

// The menu bar popover — Clonk's whole UI. The popover sizes its height
// to whichever tab is open.
struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var tab: PopoverTab = .sounds
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(PopoverTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 12)

            tabContent
        }
        .padding(16)
        .frame(width: 460)
        .onExitCommand { NSApp.keyWindow?.close() }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .settings: settingsTab
        case .sounds: soundsTab
        case .triggers: TriggersTab(model: model)
        case .profiles: ProfilesTab(model: model)
        case .stats: StatsTab(model: model)
        case .about: aboutTab
        }
    }

    // MARK: - Settings

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection("Keyboard") {
                ToggleRow("Press sound", isOn: $model.keySoundEnabled)
                Divider()
                ToggleRow("Release sound", isOn: $model.releaseSoundEnabled)
                Divider()
                ToggleRow("Mute modifiers", isOn: $model.muteModifiers)
            }
            CardSection("Mouse") {
                ToggleRow("Click sound", isOn: $model.mouseSoundEnabled)
                Divider()
                ToggleRow("Release sound", isOn: $model.mouseReleaseEnabled)
            }
            CardSection("Scroll") {
                ToggleRow("Scroll sound", isOn: $model.scrollSoundEnabled)
                Divider()
                HStack {
                    Text("Sensitivity")
                    Slider(value: $model.scrollSensitivity, in: 0...1)
                    Text("\(Int(model.scrollSensitivity * 100))%")
                        .monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .disabled(!model.scrollSoundEnabled)
            }
            CardSection("Volume") {
                VolumeRow(label: "Master", value: $model.volume)
                Divider()
                VolumeRow(label: "Keyboard", value: $model.keyVolume)
                Divider()
                VolumeRow(label: "Mouse", value: $model.mouseVolume)
                Divider()
                VolumeRow(label: "Scroll", value: $model.scrollVolume)
            }
            SpatialSection(model: model)
            VisualizersSection(model: model)
        }
    }

    // MARK: - Sounds

    private var soundsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection(nil) {
                HStack(spacing: 10) {
                    Text("Keyboard Sound").frame(width: 108, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("", selection: keyboardSoundBinding) {
                        ForEach(Theme.builtIns) { Text($0.name).tag($0.id) }
                        Divider()
                        Text("Custom (sample pack)").tag(AppModel.customID)
                        Divider()
                        Text("Piano").tag(AppModel.pianoID)
                    }
                    .labelsHidden()
                    .frame(width: 152)
                    PlayButton {
                        if model.pianoModeEnabled { model.previewPiano() } else { model.preview() }
                    }
                }
                .padding(.vertical, 6)
                if model.pianoModeEnabled {
                    PianoControls(model: model)
                } else {
                    Divider()
                    ToggleRow("Advanced", isOn: $model.keyboardAdvancedEnabled)
                    if model.keyboardAdvancedEnabled {
                        KeyboardEditor(model: model)
                            .padding(.top, 6)
                    }
                }
            }

            if model.isCustom && !model.pianoModeEnabled {
                CardSection("Sample Pack") {
                    HStack {
                        Picker("Pack", selection: packBinding) {
                            Text("None").tag(String?.none)
                            ForEach(model.installedPacks) { pack in
                                Text("\(pack.name) (\(pack.fileCount))").tag(String?.some(pack.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, 2)
                    Divider()
                    HStack {
                        Button("Import Folder…") { importPack() }
                        if let pack = model.activePack {
                            Button("Delete", role: .destructive) { model.deletePack(pack) }
                        }
                    }
                    .padding(.vertical, 4)
                    Text("A folder of audio files (wav, aiff, caf, mp3, m4a, flac). Clonk plays a random file per keystroke.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CardSection(nil) {
                HStack(spacing: 10) {
                    Text("Mouse Sound").frame(width: 108, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("", selection: $model.mouseThemeID) {
                        ForEach(Theme.mouseVoices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 152)
                    PlayButton { model.previewMouse() }
                }
                .padding(.vertical, 6)
                Divider()
                ToggleRow("Advanced", isOn: $model.mouseAdvancedEnabled)
                if model.mouseAdvancedEnabled {
                    MouseAdvancedEditor(model: model)
                        .padding(.top, 6)
                }
            }

            CardSection(nil) {
                HStack(spacing: 10) {
                    Text("Scroll Sound").frame(width: 108, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("", selection: $model.scrollThemeID) {
                        ForEach(Theme.scrollVoices) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 152)
                    PlayButton { model.previewScroll() }
                }
                .padding(.vertical, 6)
                Divider()
                ToggleRow("Advanced", isOn: $model.scrollAdvancedEnabled)
                if model.scrollAdvancedEnabled {
                    ScrollAdvancedEditor(model: model)
                        .padding(.top, 6)
                }
            }

            CardSection("Playground") {
                SoundPlayground(model: model, height: 80)
                Text("Type and click here to test your sound.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection(nil) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clonk").font(.headline)
                        Text("Version 1.0").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isMuted {
                        Label("Sleeping", systemImage: "moon.zzz.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            CardSection("Permissions") {
                if model.accessibilityGranted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Clonk needs permission to hear keystrokes so it can play a click. Sound is synthesised on your Mac — nothing is recorded, stored, or sent anywhere.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    HStack {
                        Button("Request Access") { model.requestAccessibility() }
                        Button("Open Settings…") { openAccessibilityPane() }
                    }
                    .padding(.top, 2)
                }
            }
            CardSection(nil) {
                HStack {
                    Spacer()
                    Button("Quit Clonk") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q", modifiers: .command)
                }
            }
        }
    }

    // MARK: - Helpers

    private var packBinding: Binding<String?> {
        Binding(get: { model.samplePackID }, set: { model.samplePackID = $0 })
    }

    private var keyboardSoundBinding: Binding<String> {
        Binding(
            get: { model.pianoModeEnabled ? AppModel.pianoID : model.themeID },
            set: { newValue in
                if newValue == AppModel.pianoID {
                    model.pianoModeEnabled = true
                } else {
                    model.pianoModeEnabled = false
                    model.themeID = newValue
                }
            }
        )
    }

    private func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a folder of audio files for a Clonk sample pack."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.importPack(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - Piano Mode

private struct PianoControls: View {
    @Bindable var model: AppModel

    private static let rootChoices: [(Int, String)] = [
        (36, "C2"), (43, "G2"),
        (48, "C3"), (55, "G3"),
        (60, "C4"), (62, "D4"), (64, "E4"), (65, "F4"), (67, "G4"), (69, "A4"),
        (72, "C5"), (76, "E5"), (79, "G5"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Text("Scale").frame(width: 108, alignment: .leading)
                Spacer(minLength: 0)
                Picker("", selection: Binding(
                    get: { model.pianoConfig.scale },
                    set: { var c = model.pianoConfig; c.scale = $0; model.pianoConfig = c }
                )) {
                    ForEach(PianoScale.allCases) { Text($0.name).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.vertical, 6)
            Divider()
            HStack(spacing: 10) {
                Text("Root note").frame(width: 108, alignment: .leading)
                Spacer(minLength: 0)
                Picker("", selection: Binding(
                    get: { model.pianoConfig.rootMidi },
                    set: { var c = model.pianoConfig; c.rootMidi = $0; model.pianoConfig = c }
                )) {
                    ForEach(Self.rootChoices, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.vertical, 6)
            Divider()
            HStack(spacing: 10) {
                Text("Sustain").frame(width: 108, alignment: .leading)
                Slider(value: Binding(
                    get: { model.pianoConfig.sustain },
                    set: { var c = model.pianoConfig; c.sustain = $0; model.pianoConfig = c }
                ), in: 0.4...2.0)
                Text(String(format: "%.1f×", model.pianoConfig.sustain))
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
            }
            .padding(.vertical, 6)
            Divider()
            ToggleRow("Modifier keys sustain", isOn: Binding(
                get: { model.pianoConfig.modifierSustain },
                set: { var c = model.pianoConfig; c.modifierSustain = $0; model.pianoConfig = c }
            ))
            Text("Keyboard rows climb octaves; each row uses the chosen scale so mashing always sounds musical.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Spatial / Visualizers sections

private struct SpatialSection: View {
    @Bindable var model: AppModel

    var body: some View {
        CardSection("Spatial Audio") {
            ToggleRow("3D positional sound", isOn: Binding(
                get: { model.spatialConfig.enabled },
                set: { model.spatialConfig.enabled = $0 }
            ))
            if model.spatialConfig.enabled {
                Divider()
                ToggleRow("HRTF (headphones)", isOn: Binding(
                    get: { model.spatialConfig.hrtf },
                    set: { model.spatialConfig.hrtf = $0 }
                ))
                Divider()
                HStack {
                    Text("Width")
                    Slider(value: Binding(
                        get: { model.spatialConfig.width },
                        set: { model.spatialConfig.width = $0 }
                    ), in: 0...1)
                }.padding(.vertical, 6)
                HStack {
                    Text("Distance")
                    Slider(value: Binding(
                        get: { model.spatialConfig.distance },
                        set: { model.spatialConfig.distance = $0 }
                    ), in: 0...1)
                }.padding(.vertical, 6)
            }
        }
    }
}

private struct VisualizersSection: View {
    @Bindable var model: AppModel

    var body: some View {
        CardSection("Visualizers") {
            ToggleRow("Key visualizer", isOn: $model.keyVizEnabled)
            if model.keyVizEnabled {
                HStack {
                    Text("Style").font(.callout)
                    Spacer()
                    Picker("", selection: $model.keyVizStyle) {
                        ForEach(KeyVizStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                .padding(.vertical, 4)
            }
            Divider()
            ToggleRow("WPM visualizer", isOn: $model.wpmVizEnabled)
            if model.keyVizEnabled || model.wpmVizEnabled {
                Text("Floating windows appear above all spaces. Drag from the background to move.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Triggers tab

private struct TriggersTab: View {
    @Bindable var model: AppModel
    @State private var expanded: UUID?

    private var cfg: Binding<TriggersConfig> {
        Binding(get: { model.triggersConfig }, set: { model.triggersConfig = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection(nil) {
                ToggleRow("Enable sleep triggers", isOn: cfg.enabled)
                Text("Mute Clonk automatically when any enabled rule matches.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isMuted {
                    Divider()
                    Label("Currently sleeping", systemImage: "moon.zzz.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                }
            }

            CardSection("Rules") {
                if model.triggersConfig.rules.isEmpty {
                    Text("No rules yet. Add one below.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(model.triggersConfig.rules.enumerated()), id: \.element.id) { idx, rule in
                        if idx > 0 { Divider() }
                        RuleRow(
                            rule: ruleBinding(at: idx),
                            isActive: model.triggersManager.isActive(rule),
                            isExpanded: expanded == rule.id,
                            toggleExpand: {
                                expanded = expanded == rule.id ? nil : rule.id
                            },
                            onDelete: { deleteRule(rule.id) }
                        )
                    }
                }
                Divider()
                HStack {
                    Menu {
                        ForEach(TriggerKind.templates, id: \.typeID) { kind in
                            Button {
                                addRule(kind: kind)
                            } label: {
                                Label(kind.label, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .disabled(!model.triggersConfig.enabled)
            .opacity(model.triggersConfig.enabled ? 1 : 0.5)
        }
    }

    private func ruleBinding(at index: Int) -> Binding<TriggerRule> {
        Binding(
            get: {
                let rules = model.triggersConfig.rules
                return index < rules.count ? rules[index] : TriggerRule(kind: .externalKeyboard)
            },
            set: { newValue in
                var c = model.triggersConfig
                guard index < c.rules.count else { return }
                c.rules[index] = newValue
                model.triggersConfig = c
            }
        )
    }

    private func addRule(kind: TriggerKind) {
        var c = model.triggersConfig
        let rule = TriggerRule(name: kind.label, kind: kind)
        c.rules.append(rule)
        model.triggersConfig = c
        expanded = rule.id
    }

    private func deleteRule(_ id: UUID) {
        var c = model.triggersConfig
        c.rules.removeAll { $0.id == id }
        model.triggersConfig = c
        if expanded == id { expanded = nil }
    }
}

private struct RuleRow: View {
    @Binding var rule: TriggerRule
    let isActive: Bool
    let isExpanded: Bool
    let toggleExpand: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: rule.kind.symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(rule.name.isEmpty ? rule.kind.label : rule.name)
                            .font(.callout)
                        if isActive {
                            Circle().fill(.green).frame(width: 6, height: 6)
                        }
                    }
                    Text((rule.invert ? "Mute except " : "Mute ") + rule.kind.summary)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    toggleExpand()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                Toggle("", isOn: $rule.enabled).toggleStyle(.switch).labelsHidden()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { toggleExpand() }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Name").frame(width: 70, alignment: .leading).font(.caption)
                        TextField("Name", text: $rule.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Toggle("Invert (mute when NOT matching)", isOn: $rule.invert)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        Spacer()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    TriggerKindEditor(kind: $rule.kind)
                }
                .padding(.vertical, 6)
                .padding(.leading, 26)
            }
        }
    }
}

private struct TriggerKindEditor: View {
    @Binding var kind: TriggerKind

    var body: some View {
        switch kind {
        case .schedule:
            ScheduleEditor(kind: $kind)
        case .appFocus:
            AppFocusEditor(kind: $kind)
        case .lowBattery:
            LowBatteryEditor(kind: $kind)
        case .idle:
            IdleEditor(kind: $kind)
        default:
            EmptyView()
        }
    }
}

private struct ScheduleEditor: View {
    @Binding var kind: TriggerKind

    var body: some View {
        let (start, end, days) = unpack
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("From").font(.caption).frame(width: 50, alignment: .leading)
                Stepper(value: Binding(
                    get: { start / 60 },
                    set: { set(start: $0 * 60, end: end, days: days) }
                ), in: 0...23) {
                    Text(String(format: "%02d:00", start / 60)).monospacedDigit()
                }
                Text("to").font(.caption)
                Stepper(value: Binding(
                    get: { end / 60 },
                    set: { set(start: start, end: $0 * 60, days: days) }
                ), in: 0...23) {
                    Text(String(format: "%02d:00", end / 60)).monospacedDigit()
                }
            }
            HStack(spacing: 4) {
                Text("Days").font(.caption).frame(width: 50, alignment: .leading)
                ForEach(1...7, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        var next = days
                        if on { next.removeAll { $0 == d } } else { next.append(d) }
                        set(start: start, end: end, days: next)
                    } label: {
                        Text(dayLetter(d))
                            .font(.caption.weight(.medium))
                            .frame(width: 24, height: 22)
                            .background(on ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.quaternary))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                Text(days.isEmpty ? "(every day)" : "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var unpack: (Int, Int, [Int]) {
        if case let .schedule(s, e, d) = kind { return (s, e, d) }
        return (9 * 60, 17 * 60, [])
    }

    private func set(start: Int, end: Int, days: [Int]) {
        kind = .schedule(startMinute: start, endMinute: end, weekdays: days.sorted())
    }

    private func dayLetter(_ d: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][d - 1]
    }
}

private struct AppFocusEditor: View {
    @Binding var kind: TriggerKind
    @State private var newBundle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ids, id: \.self) { id in
                HStack {
                    Text(id).font(.caption.monospaced())
                    Spacer()
                    Button {
                        set(ids.filter { $0 != id })
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Bundle ID (e.g. us.zoom.xos)", text: $newBundle)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newBundle.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !ids.contains(trimmed) else { return }
                    set(ids + [trimmed])
                    newBundle = ""
                }
                .disabled(newBundle.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Front App") {
                    if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
                        newBundle = id
                    }
                }
            }
        }
    }

    private var ids: [String] {
        if case let .appFocus(list) = kind { return list }
        return []
    }

    private func set(_ list: [String]) {
        kind = .appFocus(bundleIDs: list)
    }
}

private struct LowBatteryEditor: View {
    @Binding var kind: TriggerKind

    var body: some View {
        let pct = current
        HStack {
            Text("Threshold").font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: Binding(
                get: { Double(pct) },
                set: { kind = .lowBattery(percent: Int($0)) }
            ), in: 5...95, step: 5)
            Text("\(pct)%").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
    }

    private var current: Int {
        if case let .lowBattery(p) = kind { return p }
        return 20
    }
}

private struct IdleEditor: View {
    @Binding var kind: TriggerKind

    var body: some View {
        let secs = current
        HStack {
            Text("After").font(.caption).frame(width: 50, alignment: .leading)
            Slider(value: Binding(
                get: { Double(secs) },
                set: { kind = .idle(seconds: Int($0)) }
            ), in: 30...1800, step: 30)
            Text(label(secs)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }

    private var current: Int {
        if case let .idle(s) = kind { return s }
        return 300
    }

    private func label(_ s: Int) -> String {
        s >= 60 ? "\(s / 60) min" : "\(s)s"
    }
}

// MARK: - Profiles tab

private struct ProfilesTab: View {
    @Bindable var model: AppModel
    @State private var renameTarget: String?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection("Active Profile") {
                HStack {
                    Picker("", selection: Binding(
                        get: { model.active.id },
                        set: { model.switchProfile(to: $0) }
                    )) {
                        ForEach(model.profiles) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer()
                }
                .padding(.vertical, 4)
                Divider()
                HStack {
                    Button("New…") {
                        model.newProfile(named: "New Profile")
                        renameTarget = model.active.id
                        renameText = model.active.name
                    }
                    Button("Duplicate") { model.duplicateActive(); model.reloadProfiles() }
                    Button("Rename") {
                        renameTarget = model.active.id
                        renameText = model.active.name
                    }
                    Spacer()
                    Button("Delete", role: .destructive) {
                        model.deleteProfile(model.active.id)
                    }
                    .disabled(model.profiles.count <= 1)
                }
                .padding(.vertical, 4)
            }

            if let target = renameTarget {
                CardSection("Rename") {
                    HStack {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            model.rename(profileID: target, to: renameText)
                            renameTarget = nil
                        }
                        Button("Cancel") { renameTarget = nil }
                    }
                    .padding(.vertical, 4)
                }
            }

        }
    }
}

// MARK: - Stats tab

private struct StatsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection("Usage Stats") {
                ToggleRow("Track usage (local only)", isOn: $model.statsEnabled)
                Text("Counts stay on your Mac. Nothing is recorded, stored elsewhere, or sent anywhere. Default off.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.statsEnabled || model.statsSnapshot.totalKeys > 0 {
                let s = model.statsSnapshot
                CardSection("Totals") {
                    statRow("Keystrokes", "\(s.totalKeys)")
                    Divider()
                    statRow("Mouse clicks", "\(s.totalMouse)")
                    Divider()
                    statRow("Scroll ticks", "\(s.totalScrolls)")
                    Divider()
                    statRow("Peak WPM", String(format: "%.0f", s.peakWPM))
                }
                CardSection("Daily (last 30)") {
                    DailyBarChart(daily: s.daily)
                        .frame(height: 80)
                }
                CardSection("Manage") {
                    HStack {
                        Button("Export CSV…") { exportCSV() }
                        Spacer()
                        Button("Reset", role: .destructive) { model.resetStats() }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "clonk-stats.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.exportStatsCSV().data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

private struct DailyBarChart: View {
    let daily: [String: Int]

    var body: some View {
        let sorted = daily.sorted { $0.key < $1.key }.suffix(30)
        let peak = max(sorted.map(\.value).max() ?? 1, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(sorted), id: \.key) { day in
                    Rectangle()
                        .fill(.tint)
                        .frame(height: geo.size.height * Double(day.value) / Double(peak))
                }
            }
        }
    }
}

// MARK: - Building blocks

private struct CardSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VolumeRow: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 72, alignment: .leading)
            Slider(value: $value, in: 0...1)
            Text("\(Int(value * 100))%")
                .monospacedDigit().frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

struct PlayButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .help("Preview")
    }
}

private struct ToggleRow: View {
    let label: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ label: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Tabs

enum PopoverTab: String, CaseIterable, Identifiable {
    case settings, sounds, triggers, profiles, stats, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .sounds: return "Sounds"
        case .triggers: return "Sleep"
        case .profiles: return "Profiles"
        case .stats: return "Stats"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .sounds: return "waveform"
        case .triggers: return "moon.zzz"
        case .profiles: return "person.crop.circle"
        case .stats: return "chart.bar"
        case .about: return "info.circle"
        }
    }
}
