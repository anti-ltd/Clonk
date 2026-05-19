import SwiftUI

// Per-button mouse override list. Three rows: left / right / middle.
struct MouseAdvancedEditor: View {
    let model: AppModel
    private let buttons: [(Int, String)] = [(0, "Left"), (1, "Right"), (2, "Middle")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(buttons, id: \.0) { (button, label) in
                MouseOverrideRow(model: model, button: button, label: label)
            }
        }
    }
}

private struct MouseOverrideRow: View {
    let model: AppModel
    let button: Int
    let label: String

    @State private var themeID: String = ""
    @State private var pitch: Double = 1.0

    private var isPressed: Bool { model.pressedMouseButtons.contains(button) }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 56, alignment: .leading)
            Picker("", selection: $themeID) {
                Text("Inherit").tag("")
                ForEach(Theme.mouseVoices) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 130)
            Slider(value: $pitch, in: 0.6...1.5)
                .disabled(themeID.isEmpty)
            Text("\(Int(pitch * 100))%")
                .monospacedDigit().frame(width: 40, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(themeID.isEmpty ? .secondary : .primary)
            PlayButton { preview() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPressed ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.clear))
        )
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .onAppear { load() }
        .onChange(of: themeID) { _, _ in apply() }
        .onChange(of: pitch) { _, _ in apply() }
    }

    private func load() {
        if let o = model.advanced.mouse[button] {
            themeID = o.themeID; pitch = o.pitchMul
        } else {
            themeID = ""; pitch = 1.0
        }
    }
    private func apply() {
        if themeID.isEmpty {
            model.setMouseOverride(button, nil)
        } else {
            model.setMouseOverride(button, VoiceOverride(themeID: themeID, pitchMul: pitch))
        }
    }
    private func preview() {
        if let theme = Theme.any(id: themeID) {
            model.previewOverride(theme: theme, basePitch: pitch)
        } else {
            model.previewMouse()
        }
    }
}

// Per-direction scroll override list. Two rows: up / down.
struct ScrollAdvancedEditor: View {
    let model: AppModel
    private let dirs: [(String, String)] = [("up", "Scroll Up"), ("down", "Scroll Down")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(dirs, id: \.0) { (dir, label) in
                ScrollOverrideRow(model: model, direction: dir, label: label)
            }
        }
    }
}

private struct ScrollOverrideRow: View {
    let model: AppModel
    let direction: String
    let label: String

    @State private var themeID: String = ""
    @State private var pitch: Double = 1.0
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 80, alignment: .leading)
            Picker("", selection: $themeID) {
                Text("Inherit").tag("")
                ForEach(Theme.scrollVoices) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 130)
            Slider(value: $pitch, in: 0.6...1.5)
                .disabled(themeID.isEmpty)
            Text("\(Int(pitch * 100))%")
                .monospacedDigit().frame(width: 40, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(themeID.isEmpty ? .secondary : .primary)
            PlayButton { preview() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(pulse ? AnyShapeStyle(.tint.opacity(0.30)) : AnyShapeStyle(.clear))
        )
        .animation(.easeOut(duration: 0.18), value: pulse)
        .onAppear { load() }
        .onChange(of: themeID) { _, _ in apply() }
        .onChange(of: pitch) { _, _ in apply() }
        .onChange(of: model.scrollPulses[direction] ?? 0) { _, _ in
            pulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pulse = false }
        }
    }

    private func load() {
        if let o = model.advanced.scroll[direction] {
            themeID = o.themeID; pitch = o.pitchMul
        } else {
            themeID = ""; pitch = 1.0
        }
    }
    private func apply() {
        if themeID.isEmpty {
            model.setScrollOverride(direction, nil)
        } else {
            model.setScrollOverride(direction, VoiceOverride(themeID: themeID, pitchMul: pitch))
        }
    }
    private func preview() {
        if let theme = Theme.any(id: themeID) {
            model.previewOverride(theme: theme, basePitch: pitch)
        } else {
            model.previewScroll()
        }
    }
}
