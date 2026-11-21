import SwiftUI

/// The right-click menu for one or more snippets, also used by the Snippet menu in the menu bar.
struct SnippetActionsMenu: View {
    let ids: Set<Snippet.ID>
    let onDelete: (Set<Snippet.ID>) -> Void

    @Environment(AppState.self) private var state

    private var store: SnippetStore { state.store }
    private var snippets: [Snippet] { ids.compactMap(store.snippet) }
    private var single: Snippet? { snippets.count == 1 ? snippets.first : nil }

    var body: some View {
        let allOn = !snippets.isEmpty && snippets.allSatisfy(\.isEnabled)

        Button(allOn ? "Turn Off" : "Turn On", systemImage: allOn ? "pause.circle" : "play.circle") {
            for id in ids { store.setEnabled(id, !allOn) }
        }

        if let single {
            Button("Insert Now", systemImage: "text.insert") {
                state.insert(single, after: 0.35)
                NSApp.hide(nil)
            }
            Button("Copy Text", systemImage: "doc.on.doc") {
                state.copyExpansion(single.id)
            }
        }

        Button(ids.count == 1 ? "Duplicate" : "Duplicate \(ids.count) Snippets", systemImage: "plus.square.on.square") {
            state.selection = Set(ids.map { .snippet($0) })
            state.duplicateSelection()
        }

        Divider()

        Menu("Move to Group", systemImage: "folder") {
            Button("No Group") { store.move(ids, to: nil) }
            if !store.groups.isEmpty { Divider() }
            ForEach(store.groups) { group in
                Button(group.name, systemImage: group.symbol) { store.move(ids, to: group.id) }
            }
            Divider()
            Button("New Group…") {
                let group = store.addGroup()
                store.move(ids, to: group.id)
                state.renamingGroupID = group.id
            }
        }

        Menu("Expands", systemImage: "keyboard") {
            Picker("Expands", selection: binding(\.mode, fallback: .afterDelimiter)) {
                ForEach(ExpansionMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Menu("Animation", systemImage: "sparkles") {
            Picker("Animation", selection: binding(\.animation, fallback: nil)) {
                Text("Default (\(state.defaultAnimation.title))").tag(ReplacementAnimation?.none)
                Divider()
                ForEach(ReplacementAnimation.allCases) { style in
                    Label(style.title, systemImage: style.symbol).tag(Optional(style))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        if ids.count == 1, let id = ids.first {
            Button("Choose Icon…", systemImage: "face.smiling") {
                state.iconPickerTarget = .snippet(id)
            }
        }

        Divider()

        Button(ids.count == 1 ? "Delete" : "Delete \(ids.count) Snippets", systemImage: "trash", role: .destructive) {
            onDelete(ids)
        }
    }

    /// A binding that reads the first snippet's value and writes to all of them.
    private func binding<Value>(_ keyPath: WritableKeyPath<Snippet, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: { snippets.first?[keyPath: keyPath] ?? fallback },
            set: { value in
                for id in ids { store.update(id) { $0[keyPath: keyPath] = value } }
            }
        )
    }
}

/// The right-click menu for a group header.
struct GroupActionsMenu: View {
    let group: SnippetGroup
    @Environment(AppState.self) private var state

    var body: some View {
        let store = state.store

        Button("New Snippet in \u{201C}\(group.name)\u{201D}", systemImage: "square.and.pencil") {
            state.newSnippet(in: group.id)
        }
        Button(group.isEnabled ? "Turn Group Off" : "Turn Group On", systemImage: group.isEnabled ? "pause.circle" : "play.circle") {
            store.updateGroup(group.id) { $0.isEnabled.toggle() }
        }
        Button(group.isExpanded ? "Collapse Group" : "Expand Group",
               systemImage: group.isExpanded ? "chevron.up" : "chevron.down") {
            store.updateGroup(group.id) { $0.isExpanded.toggle() }
        }
        Button("Rename…", systemImage: "pencil") {
            state.renamingGroupID = group.id
        }
        let index = store.groups.firstIndex { $0.id == group.id } ?? 0
        Button("Move Up", systemImage: "arrow.up") { store.moveGroup(group.id, by: -1) }
            .disabled(index == 0)
        Button("Move Down", systemImage: "arrow.down") { store.moveGroup(group.id, by: 1) }
            .disabled(index >= store.groups.count - 1)

        Divider()

        Button("Colour…", systemImage: "paintpalette") {
            state.colorPickerGroupID = group.id
        }

        Button("Choose Icon…", systemImage: "face.smiling") {
            state.iconPickerTarget = .group(group.id)
        }

        Divider()

        Button("Delete Group…", systemImage: "trash", role: .destructive) {
            state.deletingGroupID = group.id
        }
    }
}
