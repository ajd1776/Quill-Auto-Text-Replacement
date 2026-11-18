import SwiftUI

/// Choose a group's colour: a preset, a recent custom colour, or any colour from the system colour panel.
struct GroupColorPicker: View {
    let groupID: SnippetGroup.ID
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recentCustomColors") private var recentStorage = ""
    @State private var custom: Color = .purple

    private var group: SnippetGroup? { state.store.group(groupID) }
    private var recents: [String] { recentStorage.split(separator: ",").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SnippetIcon(symbol: group?.symbol, color: group?.tint, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Group Colour").font(.headline)
                    Text(group?.name ?? "").foregroundStyle(.secondary)
                }
                Spacer()
            }

            section("Presets") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 6), spacing: 10) {
                    ForEach(GroupColor.allCases) { preset in
                        Swatch(color: preset.color, isSelected: group?.customColor == nil && group?.color == preset) {
                            state.store.updateGroup(groupID) {
                                $0.color = preset
                                $0.customColor = nil
                            }
                        }
                        .help(preset.title)
                    }
                }
            }

            if !recents.isEmpty {
                section("Recent") {
                    HStack(spacing: 10) {
                        ForEach(recents, id: \.self) { hex in
                            if let color = Color(hex: hex) {
                                Swatch(color: color, isSelected: group?.customColor == hex) { apply(hex) }
                                    .help(hex)
                            }
                        }
                    }
                }
            }

            section("Custom") {
                HStack(spacing: 12) {
                    ColorPicker("Pick any colour", selection: $custom, supportsOpacity: false)
                    Spacer()
                    Button("Use This Colour") {
                        if let hex = custom.hexString { apply(hex) }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 340)
        .onAppear {
            if let hex = group?.customColor, let color = Color(hex: hex) { custom = color }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func apply(_ hex: String) {
        state.store.updateGroup(groupID) { $0.customColor = hex }
        // Keep the eight most recent custom colours, newest first.
        recentStorage = ([hex] + recents.filter { $0 != hex }).prefix(8).joined(separator: ",")
    }
}

private struct Swatch: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isSelected ? color : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
