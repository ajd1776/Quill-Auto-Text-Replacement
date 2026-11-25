import SwiftUI

/// First-run tour in five steps: what Quill does, Accessibility access, bringing in quills
/// (macOS Text Replacements and starter packs), the space after a quill, and where to find things.
struct WelcomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var step = 0
    @State private var launchesAtLogin = true
    @State private var hasRequestedAccess = false
    @State private var replacements: [MacReplacementsImporter.Entry]?
    @State private var importedCount: Int?

    private let steps = ["Welcome", "Access", "Quills", "Spacing", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: intro
                case 1: access
                case 2: snippets
                case 3: spacing
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))

            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .clipped()
        #if DEBUG
        .onAppear {
            // Screenshots of a given step: -QuillWelcomeStep 2
            if let index = CommandLine.arguments.firstIndex(of: "-QuillWelcomeStep"), index + 1 < CommandLine.arguments.count,
               let value = Int(CommandLine.arguments[index + 1]) { step = value }
        }
        #endif
        .tracksWindow(WindowID.welcome)
    }

    // MARK: Steps

    private var intro: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Welcome to Quill")
                    .font(.largeTitle.weight(.bold))
                Text("Type a short shortcut anywhere on your Mac and Quill replaces it with the full text.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("keyboard", .blue, "Works in every app", "Mail, Safari, Notes, Messages, Slack and the rest.")
                feature("text.bubble", .purple, "Suggests as you type", "A bubble above your text shows matching quills.")
                feature("lock.fill", .green, "Private by design", "Quills stay on this Mac. Password fields are always skipped.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var access: some View {
        VStack(spacing: 18) {
            StepIcon(symbol: "hand.raised.fill", color: .blue)
            VStack(spacing: 8) {
                Text("Allow Accessibility Access")
                    .font(.title.weight(.bold))
                Text("Quill needs it to notice your shortcuts and type the replacement. What you type never leaves your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if state.isTrusted {
                    Label("Quill has access. You're all set.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else if hasRequestedAccess {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for access…")
                        }
                        Text("In System Settings, open Privacy & Security › Accessibility and turn on Quill. This updates by itself.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open System Settings") { state.openAccessibilitySettings() }
                    }
                } else {
                    Button("Allow Access…") {
                        hasRequestedAccess = true
                        state.requestAccess()
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                    .accessibilityIdentifier("welcome-allow")
                }
            }
            .frame(minHeight: 90)

            Toggle("Open Quill when you log in", isOn: $launchesAtLogin)
                .toggleStyle(.switch)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var snippets: some View {
        VStack(spacing: 16) {
            StepIcon(symbol: "square.stack.3d.up.fill", color: .orange)
            VStack(spacing: 6) {
                Text("Bring In Your Quills")
                    .font(.title.weight(.bold))
                Text("Start with what you already use, add a pack, or skip this and make your own.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    SnippetIcon(symbol: "keyboard", color: .gray, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("macOS Text Replacements").font(.headline)
                        Text(replacementsDetail).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let importedCount {
                        Label(importedCount == 0 ? "Up to Date" : "Imported", systemImage: "checkmark")
                            .foregroundStyle(.green)
                    } else {
                        Button("Import") { importReplacements() }
                            .disabled((replacements ?? []).isEmpty)
                            .accessibilityIdentifier("welcome-import")
                    }
                }
                .padding(12)

                ForEach(StarterPack.all) { pack in
                    Divider().padding(.leading, 58)
                    PackRow(pack: pack)
                        .padding(12)
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onAppear(perform: loadReplacements)
    }

    /// Asks whether the space typed to expand a shortcut should stay. Removing it is the default.
    private var spacing: some View {
        VStack(spacing: 18) {
            StepIcon(symbol: "space", color: .blue)
            VStack(spacing: 6) {
                Text("The Space After a Quill")
                    .font(.title.weight(.bold))
                Text("You type a space to expand a shortcut. Should that space stay after the text?")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                SpacingChoice(title: "Remove the space", badge: "Recommended",
                              example: "Email name@example.com|",
                              detail: "The text ends right where you want it. Return, Tab and punctuation still go through.",
                              isSelected: !state.addsSpaceAfterSnippet) { state.addsSpaceAfterSnippet = false }
                    .accessibilityIdentifier("welcome-remove-space")
                SpacingChoice(title: "Keep the space", badge: nil,
                              example: "Email name@example.com |",
                              detail: "Carry on typing the next word straight away.",
                              isSelected: state.addsSpaceAfterSnippet) { state.addsSpaceAfterSnippet = true }
                    .accessibilityIdentifier("welcome-keep-space")
            }
            Text("You can change this any time in Settings › General.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            StepIcon(symbol: "checkmark", color: .green)
            VStack(spacing: 6) {
                Text("You're Ready")
                    .font(.title.weight(.bold))
                Text("Try it: type one of your shortcuts followed by a space in any app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("menubar.rectangle", .purple, "Menu bar", "Search, switch quills on and off, or pause Quill from the icon in the menu bar.")
                feature("command", .blue, "Command palette", "Press ⌘K in Quill's window to run any action or jump to a quill.")
                feature("curlybraces", .orange, "Tokens", "Add {date}, {clipboard}, {cursor} or a fill-in field with Insert Token.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(to: step - 1) }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step + 1) of \(steps.count)")
            Spacer()
            Button(step == steps.count - 1 ? "Open Quill" : "Continue") {
                if step == steps.count - 1 { finish() } else { go(to: step + 1) }
            }
            .primaryActionStyle()
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("welcome-continue")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func go(to next: Int) {
        if step == 1 { applyLaunchAtLogin() }
        withAnimation(.snappy(duration: 0.3)) { step = next }
    }

    // MARK: Pieces

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var replacementsDetail: String {
        guard let replacements else { return "Looking…" }
        if let importedCount { return importedCount == 0 ? "Already in Quill" : "Added \(importedCount) \(importedCount == 1 ? "quill" : "quills")" }
        return replacements.isEmpty ? "None found on this Mac" : "\(replacements.count) found on this Mac"
    }

    private func loadReplacements() {
        guard replacements == nil else { return }
        #if DEBUG
        if DemoLibrary.isActive {
            replacements = [.init(shortcut: "omw", phrase: "On my way!"), .init(shortcut: "brb", phrase: "be right back")]
            return
        }
        #endif
        replacements = (try? MacReplacementsImporter.loadFromSystem()) ?? []
    }

    private func importReplacements() {
        let new = (replacements ?? [])
            .filter { !state.store.containsTrigger($0.shortcut) }
            .map { Snippet(trigger: $0.shortcut, expansion: $0.phrase) }
        state.store.add(contentsOf: new)
        importedCount = new.count
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

/// One answer on the Spacing step: a title, an example with the cursor, and a check when chosen.
private struct SpacingChoice: View {
    let title: String
    let badge: String?
    let example: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(example)
                        .font(.system(.callout, design: .monospaced))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

private struct StepIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct PackRow: View {
    let pack: StarterPack
    @Environment(AppState.self) private var state

    var body: some View {
        let installed = state.store.installedGroup(for: pack) != nil
        HStack(spacing: 12) {
            SnippetIcon(symbol: pack.icon, color: pack.color.color, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(pack.name).font(.headline)
                Text(pack.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if installed {
                Button("Remove") { state.store.uninstall(pack) }
            } else {
                Button("Add") { _ = state.store.install(pack) }
            }
        }
    }
}
