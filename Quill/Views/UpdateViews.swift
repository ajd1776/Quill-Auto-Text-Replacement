import SwiftUI

/// Details of an available update: what's new, and Download, Skip or Later.
struct UpdateSheet: View {
    let release: AppRelease
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(release.name) Is Available")
                        .font(.title2.weight(.bold))
                    Text("You have \(UpdateChecker.currentVersion)." + (release.publishedAt.map { " Released \($0.formatted(date: .abbreviated, time: .omitted))." } ?? ""))
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(Self.formattedNotes(release.notes))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(height: 220)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Label("After installing, click Open Anyway in Privacy & Security, then switch Quill back on under Accessibility.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip This Version") { state.updates.skip(release) }
                Spacer()
                Button("Later") { state.updates.remindLater() }
                    .keyboardShortcut(.cancelAction)
                Button(release.downloadURL == nil ? "View Release" : "Download") { state.updates.download(release) }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle()
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    /// Release notes are Markdown; headings become bold lines, the rest renders inline.
    static func formattedNotes(_ markdown: String) -> AttributedString {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let text = String(line)
            if text.hasPrefix("#") {
                return "**" + text.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + "**"
            }
            return text.hasPrefix("- ") ? "•  " + text.dropFirst(2) : text
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: lines.joined(separator: "\n"), options: options))
            ?? AttributedString(markdown)
    }
}

/// A compact banner at the top of the sidebar while an update is waiting.
struct UpdateBanner: View {
    let release: AppRelease
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Quill \(release.version) is available")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Button("See What's New…") { state.updates.isShowingDetails = true }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.tint)
            }
            Spacer(minLength: 0)
            Button {
                state.updates.remindLater()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remind Me Later")
            .accessibilityLabel("Remind me later")
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The Updates section of Settings › General.
struct UpdateSettingsSection: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let updates = state.updates
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.checksAutomatically },
                set: { updates.checksAutomatically = $0 }
            ))
            LabeledContent("Quill \(UpdateChecker.currentVersion)") {
                HStack(spacing: 10) {
                    statusView
                    Button("Check Now") { Task { await updates.check(manual: true) } }
                        .disabled(updates.status == .checking)
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Checks GitHub Releases once a day. Nothing about you or your snippets is sent.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch state.updates.status {
        case .idle:
            if let last = state.updates.lastChecked {
                Text("Checked \(last.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
            }
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            Button("Quill \(release.version) available…") { state.updates.isShowingDetails = true }
                .buttonStyle(.link)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(1)
                .help(message)
        }
    }
}
