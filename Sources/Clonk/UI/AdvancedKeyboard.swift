import SwiftUI

// Visual keyboard for the Advanced per-key editor. Click a cap → assign a
// custom voice + pitch for that one keycode.
//
// macOS virtual key codes (Carbon HIToolbox values) — drawn as a compact ANSI
// 60%-ish layout.

struct KeyDef: Identifiable, Hashable {
    let keycode: Int
    let label: String
    let width: Double
    var id: String { "\(keycode)-\(label)" }
}

enum KeyboardLayout {
    private static func k(_ code: Int, _ label: String, _ width: Double = 1.0) -> KeyDef {
        KeyDef(keycode: code, label: label, width: width)
    }

    static let rows: [[KeyDef]] = [
        // F-row — F-keys widened so the row spans the same width as the rest.
        [k(53, "esc", 1.25),
         k(122, "F1", 1.11), k(120, "F2", 1.11), k(99, "F3", 1.11), k(118, "F4", 1.11),
         k(96, "F5", 1.11), k(97, "F6", 1.11), k(98, "F7", 1.11), k(100, "F8", 1.11),
         k(101, "F9", 1.11), k(109, "F10", 1.11), k(103, "F11", 1.11), k(111, "F12", 1.11)],
        // Number row.
        [k(50, "`"), k(18, "1"), k(19, "2"), k(20, "3"), k(21, "4"),
         k(23, "5"), k(22, "6"), k(26, "7"), k(28, "8"), k(25, "9"),
         k(29, "0"), k(27, "-"), k(24, "="), k(51, "⌫", 1.5)],
        // QWERTY row.
        [k(48, "⇥", 1.5),
         k(12, "Q"), k(13, "W"), k(14, "E"), k(15, "R"), k(17, "T"),
         k(16, "Y"), k(32, "U"), k(34, "I"), k(31, "O"), k(35, "P"),
         k(33, "["), k(30, "]"), k(42, "\\")],
        // Home row.
        [k(57, "⇪", 1.75),
         k(0, "A"), k(1, "S"), k(2, "D"), k(3, "F"), k(5, "G"),
         k(4, "H"), k(38, "J"), k(40, "K"), k(37, "L"),
         k(41, ";"), k(39, "'"), k(36, "⏎", 1.75)],
        // Bottom letter row.
        [k(56, "⇧", 2.25),
         k(6, "Z"), k(7, "X"), k(8, "C"), k(9, "V"), k(11, "B"),
         k(45, "N"), k(46, "M"), k(43, ","), k(47, "."), k(44, "/"),
         k(60, "⇧", 2.25)],
        // Modifier + space row.
        [k(63, "fn"), k(59, "⌃"), k(58, "⌥"), k(55, "⌘"),
         k(49, "space", 5.5),
         k(54, "⌘"), k(61, "⌥"),
         k(123, "←"), k(125, "↓"), k(124, "→")],
    ]

    static func name(for keycode: Int) -> String {
        for row in rows {
            for k in row where k.keycode == keycode {
                return k.label == "space" ? "Space" : k.label
            }
        }
        return "Key \(keycode)"
    }
}

private let capUnit: Double = 25
private let capGap: Double = 3
private let capHeight: Double = 28

private struct KeyCapView: View {
    let key: KeyDef
    let isOverridden: Bool
    let isSelected: Bool
    let isPressed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(key.label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: key.width * capUnit + (key.width - 1) * capGap, height: capHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                      lineWidth: 1.5)
                )
                .foregroundStyle(.primary)
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var background: AnyShapeStyle {
        if isPressed && isOverridden { return AnyShapeStyle(.tint.opacity(0.85)) }
        if isPressed { return AnyShapeStyle(.primary.opacity(0.35)) }
        if isOverridden { return AnyShapeStyle(.tint.opacity(0.45)) }
        return AnyShapeStyle(.quaternary)
    }
}

struct KeyboardEditor: View {
    let model: AppModel
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: CGFloat(capGap)) {
                    ForEach(row) { key in
                        KeyCapView(
                            key: key,
                            isOverridden: model.advanced.keys[key.keycode] != nil,
                            isSelected: selected == key.keycode,
                            isPressed: model.pressedKeys.contains(key.keycode)
                        ) {
                            selected = (selected == key.keycode) ? nil : key.keycode
                        }
                    }
                }
            }

            if let code = selected {
                KeyAssignmentEditor(model: model, keycode: code) {
                    selected = nil
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .id(code)
            } else {
                Text("Tap a key to give it a custom voice. Coloured keys already have overrides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .animation(.snappy(duration: 0.18), value: selected)
    }
}

private struct KeyAssignmentEditor: View {
    let model: AppModel
    let keycode: Int
    let onClose: () -> Void

    @State private var themeID: String = ""    // "" = inherit
    @State private var pitch: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(KeyboardLayout.name(for: keycode))
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text("Voice").frame(width: 50, alignment: .leading)
                Picker("", selection: $themeID) {
                    Text("Inherit").tag("")
                    ForEach(Theme.builtIns) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                PlayButton { preview() }
            }

            HStack(spacing: 8) {
                Text("Pitch").frame(width: 50, alignment: .leading)
                Slider(value: $pitch, in: 0.6...1.5)
                    .disabled(themeID.isEmpty)
                Text("\(Int(pitch * 100))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(themeID.isEmpty ? .secondary : .primary)
            }

            HStack {
                Button("Reset") {
                    themeID = ""
                    pitch = 1.0
                }
                Spacer()
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { load() }
        .onChange(of: keycode) { _, _ in load() }
        .onChange(of: themeID) { _, _ in apply() }
        .onChange(of: pitch) { _, _ in apply() }
    }

    private func load() {
        if let o = model.advanced.keys[keycode] {
            themeID = o.themeID
            pitch = o.pitchMul
        } else {
            themeID = ""
            pitch = 1.0
        }
    }

    private func apply() {
        if themeID.isEmpty {
            model.setKeyOverride(keycode, nil)
        } else {
            model.setKeyOverride(keycode, VoiceOverride(themeID: themeID, pitchMul: pitch))
        }
    }

    private func preview() {
        if let theme = Theme.any(id: themeID) {
            model.previewOverride(theme: theme, basePitch: pitch)
        } else {
            model.preview()
        }
    }
}
