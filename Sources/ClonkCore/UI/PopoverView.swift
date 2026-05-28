import AppKit
import SwiftUI
import iUX_MacOS

// The menu bar popover — Clonk's whole UI. The popover sizes its height
// to whichever tab is open. Chrome (tab bar, width, padding, cards, rows) comes
// from iUX-MacOS so it matches every other app; only the per-tab content lives here.
struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var tab: PopoverTab

    init(model: AppModel, initialTab: PopoverTab? = nil) {
        self._model = Bindable(wrappedValue: model)
        self._tab = State(initialValue: initialTab ?? .sounds)
    }

    var body: some View {
        // `popOutWindowID` is iUX's built-in pop-out: it places the macwindow
        // button on the right of the tab bar and opens the matching `Window`
        // scene (declared in ClonkApp) on click.
        SettingsPopover(selection: $tab, popOutWindowID: ClonkModule.windowID) { t in
            ClonkTabContent(model: model, tab: t)
        }
    }
}

// MARK: - Shared tab content (used by both the popover and the sidebar window)

struct ClonkTabContent: View {
    @Bindable var model: AppModel
    let tab: PopoverTab
    @State private var importError: String?
    @State private var settingsSubTab: SettingsSubTab = .input

    var body: some View {
        Group { content }
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
    private var content: some View {
        switch tab {
        case .settings: settingsTab
        case .sounds: soundsTab
        case .triggers: TriggersTab(model: model)
        case .profiles: ProfilesTab(model: model)
        case .stats: StatsTab(model: model)
        case .about: AboutTab(model: model)
        }
    }

    // MARK: - Settings (with subtabs)

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $settingsSubTab) {
                ForEach(SettingsSubTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            settingsSubTabContent
        }
    }

    @ViewBuilder
    private var settingsSubTabContent: some View {
        switch settingsSubTab {
        case .input:
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
        case .audio:
            CardSection("Volume") {
                SliderRow.percent("Master", value: $model.volume)
                Divider()
                SliderRow.percent("Keyboard", value: $model.keyVolume)
                Divider()
                SliderRow.percent("Mouse", value: $model.mouseVolume)
                Divider()
                SliderRow.percent("Scroll", value: $model.scrollVolume)
            }
            CardSection("Engine") {
                HStack(spacing: 10) {
                    Text("Playback").frame(width: 108, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("", selection: $model.enginePlaybackMode) {
                        ForEach(EnginePlaybackMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                .padding(.vertical, 6)
                Text(engineModeHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SpatialSection(model: model)
        case .visual:
            VisualizersSection(model: model)
        case .advanced:
            AdvancedTab(model: model)
        }
    }

    // Help text under the engine playback picker. Surfaces the auto-fallback
    // so users aren't confused when Cached doesn't actually save CPU because
    // they have piano / guitar / spatial / overrides on.
    private var engineModeHint: String {
        let forces: [String] = [
            model.pianoModeEnabled ? "Piano mode" : nil,
            model.guitarModeEnabled ? "Guitar mode" : nil,
            model.spatialConfig.enabled ? "Spatial audio" : nil,
            (model.keyboardAdvancedEnabled && !model.advanced.keys.isEmpty) ? "Keyboard overrides" : nil,
            (model.mouseAdvancedEnabled && !model.advanced.mouse.isEmpty) ? "Mouse overrides" : nil,
            (model.scrollAdvancedEnabled && !model.advanced.scroll.isEmpty) ? "Scroll overrides" : nil,
        ].compactMap { $0 }
        if model.enginePlaybackMode == .cached && !forces.isEmpty {
            return "Live engine is in use because \(forces.joined(separator: ", ")) need real-time processing."
        }
        switch model.enginePlaybackMode {
        case .cached: return "Plays pre-rendered clicks via a lightweight player pool. Idle CPU near zero."
        case .live:   return "Real-time audio engine — needed for piano, guitar, spatial, and per-key overrides."
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
                        Text("Guitar").tag(AppModel.guitarID)
                    }
                    .labelsHidden()
                    .frame(width: 152)
                    PlayButton {
                        if model.pianoModeEnabled { model.previewPiano() }
                        else if model.guitarModeEnabled { model.previewGuitar() }
                        else { model.preview() }
                    }
                }
                .padding(.vertical, 6)
                if model.pianoModeEnabled {
                    PianoControls(model: model)
                } else if model.guitarModeEnabled {
                    GuitarControls(model: model)
                } else {
                    Divider()
                    ToggleRow("Advanced", isOn: $model.keyboardAdvancedEnabled)
                    if model.keyboardAdvancedEnabled {
                        KeyboardEditor(model: model)
                            .padding(.top, 6)
                    }
                }
            }

            if model.isCustom && !model.pianoModeEnabled && !model.guitarModeEnabled {
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

    // MARK: - Helpers

    private var packBinding: Binding<String?> {
        Binding(get: { model.samplePackID }, set: { model.samplePackID = $0 })
    }

    private var keyboardSoundBinding: Binding<String> {
        Binding(
            get: {
                if model.pianoModeEnabled { return AppModel.pianoID }
                if model.guitarModeEnabled { return AppModel.guitarID }
                return model.themeID
            },
            set: { newValue in
                switch newValue {
                case AppModel.pianoID:
                    model.pianoModeEnabled = true
                case AppModel.guitarID:
                    model.guitarModeEnabled = true
                default:
                    model.pianoModeEnabled = false
                    model.guitarModeEnabled = false
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
                    ForEach(MusicalScale.allCases) { Text($0.name).tag($0) }
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

// MARK: - Guitar Mode

private struct GuitarControls: View {
    @Bindable var model: AppModel

    private static let rootChoices: [(Int, String)] = [
        (40, "E2"), (45, "A2"), (50, "D3"), (52, "E3"), (55, "G3"),
        (57, "A3"), (60, "C4"), (62, "D4"), (64, "E4"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Text("Scale").frame(width: 108, alignment: .leading)
                Spacer(minLength: 0)
                Picker("", selection: Binding(
                    get: { model.guitarConfig.scale },
                    set: { var c = model.guitarConfig; c.scale = $0; model.guitarConfig = c }
                )) {
                    ForEach(MusicalScale.allCases) { Text($0.name).tag($0) }
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
                    get: { model.guitarConfig.rootMidi },
                    set: { var c = model.guitarConfig; c.rootMidi = $0; model.guitarConfig = c }
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
                    get: { model.guitarConfig.sustain },
                    set: { var c = model.guitarConfig; c.sustain = $0; model.guitarConfig = c }
                ), in: 0.4...2.0)
                Text(String(format: "%.1f×", model.guitarConfig.sustain))
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
            }
            .padding(.vertical, 6)
            Divider()
            ToggleRow("Modifier keys sustain", isOn: Binding(
                get: { model.guitarConfig.modifierSustain },
                set: { var c = model.guitarConfig; c.modifierSustain = $0; model.guitarConfig = c }
            ))
            Text("Each keystroke plucks a string; keyboard rows climb octaves of the chosen scale so mashing always sounds musical.")
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
            ToggleRow("CPM visualizer", isOn: $model.cpmVizEnabled)
            if model.keyVizEnabled || model.wpmVizEnabled || model.cpmVizEnabled {
                Text("Floating windows appear above all spaces. Drag from the background to move.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Advanced tab

private struct AdvancedTab: View {
    @Bindable var model: AppModel

    // Smoothed press interval → approximate characters/sec for the live
    // hint under the slider. Mirrors AppModel.updateTypingRate's EMA.
    private var suppressionCPS: Double {
        let s = model.releaseSuppressInterval
        guard s > 0 else { return 0 }
        return 1.0 / s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection("Performance") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Release click suppression").font(.callout)
                        Spacer()
                        Text("\(Int(model.releaseSuppressInterval * 1000)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    Slider(value: $model.releaseSuppressInterval, in: 0...0.25)
                }
                .padding(.vertical, 4)
                Text(suppressionHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("These settings tune Clonk's audio engine for lower CPU during fast typing. Defaults are tuned for most users — adjust only if you notice missing or doubled clicks.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suppressionHint: String {
        if model.releaseSuppressInterval <= 0.0005 {
            return "Always play the release click. Highest fidelity, highest CPU at speed."
        }
        let cps = suppressionCPS
        let rate: String
        if cps >= 100 {
            rate = "very fast typing"
        } else {
            rate = String(format: "~%.0f keys/sec", cps)
        }
        return "Skip the release click when typing faster than \(rate). Cuts audio-engine load when clicks would overlap anyway."
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

// MARK: - About tab

// Owns its own state for the manual update check. There is no background
// polling; nothing fires until the user taps "Check for updates".
private struct AboutTab: View {
    @Bindable var model: AppModel
    @State private var checkState: UpdateCheckState = .idle

    private enum UpdateCheckState: Equatable {
        case idle
        case checking
        case upToDate(latest: String)
        case updateAvailable(VersionInfo)
        case failed(String)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection(nil) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clonk").font(.headline)
                        // Pull from the bundle so it tracks
                        // CFBundleShortVersionString on every release.
                        Text("Anti Limited - Version \(currentVersion)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isMuted {
                        Label("Sleeping", systemImage: "moon.zzz.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            CardSection("Updates") {
                HStack {
                    Button(action: runCheck) {
                        if case .checking = checkState {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check for updates")
                        }
                    }
                    .disabled(checkState == .checking)
                    Spacer()
                }
                updateStatusView
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

    // MARK: - Update status rendering

    @ViewBuilder
    private var updateStatusView: some View {
        switch checkState {
        case .idle, .checking:
            EmptyView()
        case .upToDate(let latest):
            Label("Up to date (\(latest))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
                .padding(.top, 2)
        case .updateAvailable(let info):
            VStack(alignment: .leading, spacing: 6) {
                Label("Update available: \(info.version)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.callout)
                if let notes = info.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = info.resolvedDownloadURL() {
                    Button("Download…") { NSWorkspace.shared.open(url) }
                        .padding(.top, 2)
                }
            }
            .padding(.top, 4)
        case .failed(let message):
            Label("Check failed: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.top, 2)
        }
    }

    // MARK: - Actions

    private func runCheck() {
        checkState = .checking
        let local = currentVersion
        Task { @MainActor in
            do {
                let info = try await UpdateChecker.fetch()
                if UpdateChecker.isNewer(info.version, than: local) {
                    checkState = .updateAvailable(info)
                } else {
                    checkState = .upToDate(latest: info.version)
                }
            } catch {
                checkState = .failed(error.localizedDescription)
            }
        }
    }

    private func openAccessibilityPane() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

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
                    Divider()
                    statRow("Peak CPM", String(format: "%.0f", s.peakCPM))
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

// MARK: - Settings window (sidebar layout)

struct SettingsWindowView: View {
    @Bindable var model: AppModel
    // Selection lives here, not inside iUX's `SettingsWindow` — the generic
    // wrapper can't host the `@State` without `NavigationSplitView` dropping
    // sidebar clicks (rows render, but selection never updates).
    @State private var selection: PopoverTab? = .settings

    var body: some View {
        // iUX's `SettingsWindow` wraps `SidebarNavigator` around the same
        // `(Tab) -> View` builder the popover uses, so the per-tab body is
        // written once in `ClonkTabContent`.
        SettingsWindow(title: "Clonk", selection: $selection) { tab in
            ClonkTabContent(model: model, tab: tab)
        }
        // Capture SwiftUI's `OpenWindowAction` so AppKit code (the menu-bar
        // "Settings" item) can open this window. The capture runs during
        // SwiftUI's brief auto-open at launch — `AppDelegate` closes the
        // window right after, but the captured action stays valid.
        .background(ClonkWindowOpenerBridge())
        #if CLONK_SHOWCASE
        // Reel showcase — installs the reel window opener (see Showcase/).
        .background(ClonkReelWindowOpenerBridge())
        #endif
    }
}

/// Bridges SwiftUI's `@Environment(\.openWindow)` to AppKit. AppKit menu
/// actions can't reach the SwiftUI environment, so we stash the action into
/// a `@MainActor` static at render time and call it from the AppDelegate.
@MainActor
public enum ClonkWindowOpener {
    public static var action: OpenWindowAction?

    /// Open the pop-out settings window and bring it forward. Safe to call
    /// from anywhere on the main actor.
    public static func open() {
        guard let action else { NSSound.beep(); return }
        action(id: ClonkModule.windowID)
        NSApp.activate(ignoringOtherApps: true)
        // `openWindow` brings the window visible but not key when the call
        // chain is an NSMenu action (the menu had first-responder), and the
        // `List`-based sidebar needs key status to hit-test. Same fix as
        // the popover's pop-out button.
        let id = ClonkModule.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let raw = window.identifier?.rawValue, raw.contains(id) else { continue }
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

private struct ClonkWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { ClonkWindowOpener.action = openWindow }
    }
}

// MARK: - Tabs

// `SettingsTab` already refines `SidebarItem`, so one conformance covers both
// the popover's segmented bar and the window's sidebar.
enum PopoverTab: String, CaseIterable, Identifiable, SettingsTab {
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

// MARK: - Settings subtabs

private enum SettingsSubTab: String, CaseIterable, Identifiable {
    case input, audio, visual, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .input: return "Input"
        case .audio: return "Audio"
        case .visual: return "Visual"
        case .advanced: return "Advanced"
        }
    }
}
