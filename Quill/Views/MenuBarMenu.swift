import SwiftUI

/// The menu shown from Quill's menu bar icon. A menu, not a popover, per the HIG.
struct MenuBarMenu: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var store: SnippetStore { state.store }

    var body: some View {
        @Bindable var state = state

        if let update = state.updates.availableUpdate {
            Button("Quill \(update.version) Is Available…") {
                openLibrary()
                state.updates.isShowingDetails = true
            }
            Divider()
        }

        Text(statusTitle)

        if state.status == .needsAccess {
            Button("Allow Accessibility Access…") {
                state.requestAccess()
                state.openAccessibilitySettings()
            }
        } else {
            Button(state.isOn ? "Turn Quill Off" : "Turn Quill On") {
                state.setOn(!state.isOn)
            }

            Menu("Pause") {
                if state.isPaused {
                    Button("Resume Now") { state.setOn(true) }
                    Divider()
                }
                Button("For 15 Minutes") { state.pause(minutes: 15) }
                Button("For 1 Hour") { state.pause(minutes: 60) }
                Button("Until Tomorrow Morning") { state.pauseUntilTomorrowMorning() }
            }

            if let app = state.lastExternalApp, let bundleID = app.bundleIdentifier {
                Toggle("Pause in \(app.localizedName ?? "This App")", isOn: Binding(
                    get: { state.isExcluded(bundleID) },
                    set: { state.setExcluded(bundleID, $0) }
                ))
            }
        }

        let recent = Array(store.recentlyUsed.prefix(5))
        if !recent.isEmpty {
            Divider()
            Section("Recent, Click to Insert") {
                ForEach(recent) { snippet in
                    Button(menuTitle(for: snippet)) { state.insert(snippet) }
                }
            }
        }

        Divider()

        Menu("Snippets") {
            let loose = store.snippets(in: nil).filter(\.hasValidTrigger).sorted(by: SnippetSortOrder.shortcut.areInIncreasingOrder)
            if store.snippets.isEmpty {
                Text("No Snippets")
            }
            ForEach(loose) { snippet in
                Toggle(menuTitle(for: snippet), isOn: store.enabledBinding(for: snippet.id))
            }
            if !loose.isEmpty, !store.groups.isEmpty { Divider() }
            ForEach(store.groups) { group in
                Menu(group.name) {
                    Toggle("Group On", isOn: store.groupEnabledBinding(for: group.id))
                    Divider()
                    ForEach(store.snippets(in: group.id).filter(\.hasValidTrigger).sorted(by: SnippetSortOrder.shortcut.areInIncreasingOrder)) { snippet in
                        Toggle(menuTitle(for: snippet), isOn: store.enabledBinding(for: snippet.id))
                    }
                }
            }
            Divider()
            Button("Show All in Library…") { openLibrary() }
        }

        Button("Search Snippets…") {
            SearchPanelController.shared.show()
        }

        Divider()

        Menu("Animation") {
            Picker("Animation", selection: $state.defaultAnimation) {
                ForEach(ReplacementAnimation.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Menu("Suggestions") {
            Toggle("Show Suggestions", isOn: $state.showsSuggestions)
            Toggle("Include Partial Matches", isOn: $state.showsPartialSuggestions)
                .disabled(!state.showsSuggestions)
            Divider()
            Picker("Position", selection: $state.bubblePosition) {
                ForEach(BubblePosition.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .disabled(!state.showsSuggestions)
        }

        Menu("Sound") {
            Picker("Sound", selection: Binding(
                get: { state.soundName },
                set: { name in
                    state.soundName = name
                    state.playSound()
                }
            )) {
                Text("None").tag(String?.none)
                Divider()
                ForEach(AppState.systemSounds, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Divider()

        Button("Overview…") {
            state.selection = [.overview]
            openLibrary()
        }
        Button("Open Library…") { openLibrary() }
            .keyboardShortcut("l")
        Button("New Snippet") {
            openLibrary()
            state.newSnippet()
        }
        .keyboardShortcut("n")
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Quill") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openLibrary() {
        NSApp.activate()
        openWindow(id: WindowID.library)
    }

    private func menuTitle(for snippet: Snippet) -> String {
        let preview = TokenRenderer.render(snippet.expansion, clipboard: "Clipboard").text.replacingOccurrences(of: "\n", with: " ")
        let short = preview.count > 30 ? String(preview.prefix(29)) + "…" : preview
        return "\(snippet.trigger)  —  \(short)"
    }

    private var statusTitle: String {
        switch state.status {
        case .on:
            let count = store.activeSnippets.count
            return "Quill Is On · \(count) \(count == 1 ? "Snippet" : "Snippets")"
        case .off:
            return "Quill Is Off"
        case .pausedUntil(let date):
            let time = date.formatted(date: .omitted, time: .shortened)
            return Calendar.current.isDateInToday(date) ? "Paused Until \(time)" : "Paused Until Tomorrow, \(time)"
        case .pausedInApp(let name):
            return "Paused in \(name)"
        case .needsAccess:
            return "Quill Needs Accessibility Access"
        }
    }
}
