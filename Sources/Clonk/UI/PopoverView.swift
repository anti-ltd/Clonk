import AppKit
import SwiftUI

// The menu bar popover — Clonk's whole UI, split across three tabs behind a
// liquid-glass tab bar. The popover sizes its height to whichever tab is open.
struct PopoverView: View {
    @Bindable var model: AppModel
    @State private var tab: PopoverTab = .sounds
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer {
                GlassTabBar(selection: $tab)
            }
            .padding(.top, 12)
            .padding(.bottom, 10)

            tabContent
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 460)
        .background(.regularMaterial)
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
        }
    }

    // MARK: - Sounds

    private var soundsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardSection(nil) {
                HStack(spacing: 10) {
                    Text("Keyboard Sound").frame(width: 108, alignment: .leading)
                    Spacer(minLength: 0)
                    Picker("", selection: $model.themeID) {
                        ForEach(Theme.builtIns) { Text($0.name).tag($0.id) }
                        Divider()
                        Text("Custom (sample pack)").tag(AppModel.customID)
                    }
                    .labelsHidden()
                    .frame(width: 152)
                    PlayButton { model.preview() }
                }
                .padding(.vertical, 6)
                Divider()
                ToggleRow("Advanced", isOn: $model.keyboardAdvancedEnabled)
                if model.keyboardAdvancedEnabled {
                    KeyboardEditor(model: model)
                        .padding(.top, 6)
                }
            }

            if model.isCustom {
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

// MARK: - Building blocks

private struct CardSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
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
        .padding(.vertical, 6)
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
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Tabs

enum PopoverTab: String, CaseIterable, Identifiable {
    case settings, sounds, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .sounds: return "Sounds"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .sounds: return "waveform"
        case .about: return "info.circle"
        }
    }
}

// Liquid-glass segmented tab bar.
private struct GlassTabBar: View {
    @Binding var selection: PopoverTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PopoverTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = tab }
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .background {
                            if selected {
                                Capsule().fill(.tint.opacity(0.20))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
