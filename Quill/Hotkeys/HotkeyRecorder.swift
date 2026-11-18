import SwiftUI

/// Click, then press a key combination to set a global shortcut.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    var label: String

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(buttonTitle)
                    .font(hotkey != nil && !isRecording ? .body.monospaced() : .body)
                    .foregroundStyle(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(minWidth: 130)
            }
            .accessibilityLabel(label)
            .accessibilityValue(hotkey?.displayString ?? "None")

            if hotkey != nil, !isRecording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear Shortcut")
                .accessibilityLabel("Clear \(label) shortcut")
            }
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if isRecording { return "Type Shortcut…" }
        return hotkey?.displayString ?? "Record Shortcut"
    }

    private func startRecording() {
        isRecording = true
        // Stop the current hotkeys firing while a new one is typed.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Esc cancels
                stopRecording()
            case 51 where event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                 117 where event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty:
                hotkey = nil
                stopRecording()
            default:
                if let recorded = Hotkey(event: event) {
                    hotkey = recorded
                    stopRecording()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        AppState.shared.registerHotkeys()
    }
}
