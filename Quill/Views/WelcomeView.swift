import SwiftUI

/// First-run window. Explains why Quill needs Accessibility access before macOS asks.
struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var launchesAtLogin = true
    @State private var hasRequestedAccess = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Welcome to Quill")
                    .font(.largeTitle.weight(.bold))
                Text("Type a short code anywhere on your Mac and Quill replaces it with the full text.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                feature("keyboard", "Works in every app", "Mail, Safari, Notes, Messages and the rest.")
                feature("lock.fill", "Private by design", "Snippets stay on this Mac. Password fields are always skipped.")
                feature("menubar.rectangle", "Out of the way", "Quill lives in the menu bar. Pause it there any time.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Launch Quill at login", isOn: $launchesAtLogin)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            footer
        }
        .padding(.horizontal, 40)
        .padding(.top, 32)
        .padding(.bottom, 28)
        .frame(width: 480)
        .tracksWindow(WindowID.welcome)
    }

    @ViewBuilder
    private var footer: some View {
        if state.isTrusted {
            VStack(spacing: 12) {
                Label("Quill can now expand your snippets.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Get Started", action: finish)
                    .primaryActionStyle()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        } else if hasRequestedAccess {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…")
                }
                Text("In System Settings, open Privacy & Security › Accessibility and turn on Quill. This window updates by itself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") {
                    state.openAccessibilitySettings()
                }
            }
        } else {
            VStack(spacing: 12) {
                Text("Next, macOS will ask you to allow Accessibility access. Quill uses it only to notice your shortcuts and type the replacement.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // One button that leads to the system prompt, as the HIG asks for pre-permission screens.
                Button("Continue") {
                    applyLaunchAtLogin()
                    hasRequestedAccess = true
                    state.requestAccess()
                }
                .primaryActionStyle()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applyLaunchAtLogin() {
        if launchesAtLogin != LoginItem.isEnabled {
            try? LoginItem.setEnabled(launchesAtLogin)
        }
    }

    private func finish() {
        applyLaunchAtLogin()
        hasCompletedWelcome = true
        openWindow(id: WindowID.library)
        dismissWindow(id: WindowID.welcome)
    }
}
