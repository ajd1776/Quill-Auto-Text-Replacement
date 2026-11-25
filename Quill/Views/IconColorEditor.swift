import SwiftUI

/// What the Icon and Colour sheet is editing or creating.
enum AppearanceTarget: Identifiable, Hashable {
    case group(SnippetGroup.ID)
    case snippet(Snippet.ID)
    case newGroup
    case newSnippet(SnippetGroup.ID?)

    var id: Self { self }

    var isSnippet: Bool {
        switch self {
        case .snippet, .newSnippet: true
        case .group, .newGroup: false
        }
    }

    var isNew: Bool {
        switch self {
        case .newGroup, .newSnippet: true
        case .group, .snippet: false
        }
    }
}

/// Everything about a group or quill in one sheet: name or shortcut, (for quills) text, notes and group,
/// colour and icon. The same sheet creates new ones and edits existing ones.
struct IconColorEditor: View {
    let target: AppearanceTarget

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("savedCustomColors") private var savedStorage = ""

    @State private var name = ""
    @State private var symbol: String?
    /// A system colour name or #RRGGBB. nil, for a snippet, means "use the group's colour".
    @State private var colorValue: String?
    @State private var groupID: SnippetGroup.ID?
    @State private var text = ""
    @State private var notes = ""
    @State private var customColor: Color = .blue
    @State private var didLoad = false
    @FocusState private var isNameFocused: Bool

    private var store: SnippetStore { state.store }
    private var saved: [String] { savedStorage.split(separator: ",").map(String.init).filter { Color(hex: $0) != nil } }
    private var group: SnippetGroup? { groupID.flatMap(store.group) }

    /// The colour the icon shows with the current choices.
    private var tint: Color {
        QuillColor.resolve(colorValue) ?? (target.isSnippet ? group?.tint : nil) ?? .accentColor
    }

    private var shownSymbol: String {
        symbol ?? (target.isSnippet ? group?.symbol : nil) ?? (target.isSnippet ? "text.quote" : "folder.fill")
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            Form {
                nameSection
                if target.isSnippet { textSection }
                colourSection
                iconSection
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(target.isNew ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validation.blocksSaving)
            }
            .padding(16)
        }
        .frame(width: 520, height: 620)
        .navigationTitle(title)
        .onAppear(perform: load)
    }

    private var title: String {
        switch target {
        case .group: "Edit Group"
        case .snippet: "Edit Quill"
        case .newGroup: "New Group"
        case .newSnippet: "New Quill"
        }
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            HStack(spacing: 14) {
                IconTile(symbol: shownSymbol, color: tint, size: 56)
                    .animation(.snappy(duration: 0.2), value: shownSymbol)
                    .animation(.snappy(duration: 0.2), value: colorValue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.isSnippet ? "Shortcut" : "Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(target.isSnippet ? "Shortcut" : "Name", text: $name,
                              prompt: Text(target.isSnippet ? "e.g. eml" : "e.g. Work"))
                        .textFieldStyle(.plain)
                        .font(target.isSnippet ? .title2.monospaced().weight(.semibold) : .title2.weight(.semibold))
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                        .labelsHidden()
                        .accessibilityLabel(target.isSnippet ? "Shortcut" : "Group name")
                        .accessibilityIdentifier("appearance-name")
                }
            }
            .padding(.vertical, 4)

            if target.isSnippet {
                Picker("Group", selection: $groupID) {
                    Text("None").tag(SnippetGroup.ID?.none)
                    if !store.groups.isEmpty { Divider() }
                    ForEach(store.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
            }
        } footer: {
            Group {
                if name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(target.isSnippet ? "Type the shortcut you'll use, and below it the text it types."
                                          : "Give the group a name.")
                        .foregroundStyle(.secondary)
                } else if let message = validation.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(validation.blocksSaving ? Color.red : Color.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var validation: (message: String?, blocksSaving: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return (target.isSnippet ? "Type the shortcut you'll use." : "Give the group a name.", true)
        }
        guard target.isSnippet else { return (nil, false) }
        if trimmed.contains(where: \.isWhitespace) { return ("Shortcuts can't contain spaces.", true) }
        let editingID: Snippet.ID? = if case .snippet(let id) = target { id } else { nil }
        if store.snippets.contains(where: { $0.trigger == trimmed && $0.id != editingID }) {
            return ("Another quill already uses this shortcut.", false)
        }
        return (nil, false)
    }

    // MARK: Text and notes

    private var textSection: some View {
        Section {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Text")
                .accessibilityIdentifier("appearance-text")
            TextField("Notes", text: $notes, prompt: Text("Add notes: what it's for, where you use it"), axis: .vertical)
                .lineLimit(1...4)
                .accessibilityIdentifier("appearance-notes")
        } header: {
            Text("Text")
        } footer: {
            Text("What the shortcut types. Tokens such as {date} or {input:Name} work here too. Notes are just for you.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Colour

    private var colourSection: some View {
        Section {
            if target.isSnippet {
                Toggle("Use the group's colour", isOn: Binding(
                    get: { colorValue == nil },
                    set: { useGroup in colorValue = useGroup ? nil : (group?.colorValue ?? GroupColor.blue.rawValue) }
                ))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                ForEach(GroupColor.allCases) { preset in
                    Swatch(color: preset.color, title: preset.title, isSelected: colorValue == preset.rawValue) {
                        colorValue = preset.rawValue
                    }
                }
            }
            .padding(.vertical, 6)

            if !saved.isEmpty {
                LabeledContent("My Colours") {
                    HStack(spacing: 10) {
                        ForEach(saved, id: \.self) { hex in
                            if let color = Color(hex: hex) {
                                Swatch(color: color, title: hex, isSelected: colorValue == hex, size: 24) {
                                    colorValue = hex
                                    customColor = color
                                }
                                .contextMenu {
                                    Button("Remove from My Colours", role: .destructive) { remove(hex) }
                                }
                            }
                        }
                    }
                }
            }

            LabeledContent("Custom Colour") {
                HStack(spacing: 10) {
                    Button("Save to My Colours", systemImage: "plus.circle") { saveCustom() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Save this colour to My Colours")
                        .disabled(saved.contains(customColor.hexString ?? ""))
                    ColorPicker("Custom Colour", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: customColor) { _, color in
                            if didLoad, let hex = color.hexString { colorValue = hex }
                        }
                }
            }

        } header: {
            Text("Colour")
        } footer: {
            Text(target.isSnippet ? "Colours this quill's icon." : "Colours the group's icon and its quills' icons.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveCustom() {
        guard let hex = customColor.hexString, !saved.contains(hex) else { return }
        savedStorage = (saved + [hex]).suffix(12).joined(separator: ",")
        colorValue = hex
    }

    private func remove(_ hex: String) {
        savedStorage = saved.filter { $0 != hex }.joined(separator: ",")
    }

    // MARK: Icon

    private var iconSection: some View {
        Section {
            IconPicker(current: symbol, tint: tint, defaultTitle: target.isSnippet ? "Use Group Icon" : nil, isEmbedded: true) { icon in
                symbol = icon
            }
            .padding(.vertical, 4)
        } header: {
            Text("Icon")
        } footer: {
            Text("Search every symbol, or switch to Emoji.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A broad set of common SF Symbols, grouped loosely by theme, so most icons are one click away.
    static let icons = [
        // Folders and objects
        "folder.fill", "archivebox.fill", "tray.fill", "tray.full.fill", "shippingbox.fill", "tag.fill", "bookmark.fill", "paperclip", "doc.fill",
        "doc.text.fill", "note.text", "list.bullet", "checklist", "square.grid.2x2.fill", "rectangle.stack.fill", "books.vertical.fill", "book.fill", "newspaper.fill",
        // Marks
        "star.fill", "heart.fill", "flag.fill", "bolt.fill", "flame.fill", "sparkles", "pin.fill", "bell.fill", "lightbulb.fill",
        "crown.fill", "trophy.fill", "rosette", "checkmark.seal.fill", "exclamationmark.triangle.fill", "questionmark.circle.fill", "info.circle.fill", "number", "textformat",
        // People and communication
        "person.fill", "person.2.fill", "person.crop.circle.fill", "envelope.fill", "phone.fill", "message.fill", "bubble.left.fill", "at", "link",
        "signature", "text.quote", "quote.bubble.fill", "megaphone.fill", "paperplane.fill", "hand.wave.fill", "hand.thumbsup.fill", "face.smiling", "video.fill",
        // Time and money
        "calendar", "clock.fill", "alarm.fill", "hourglass", "timer", "creditcard.fill", "banknote.fill", "sterlingsign.circle.fill", "dollarsign.circle.fill",
        "cart.fill", "bag.fill", "basket.fill", "gift.fill", "percent", "chart.bar.fill", "chart.pie.fill", "receipt", "barcode",
        // Places and travel
        "house.fill", "building.2.fill", "building.columns.fill", "storefront.fill", "mappin.and.ellipse", "map.fill", "globe", "location.fill", "car.fill",
        "airplane", "tram.fill", "bicycle", "figure.walk", "fork.knife", "cup.and.saucer.fill", "leaf.fill", "sun.max.fill", "moon.fill",
        // Work and tools
        "briefcase.fill", "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill", "pencil", "scissors", "ruler.fill", "printer.fill", "keyboard",
        "desktopcomputer", "laptopcomputer", "iphone", "chevron.left.forwardslash.chevron.right", "terminal.fill", "curlybraces", "gearshape.fill", "lock.fill", "key.fill",
        // Health and fun
        "cross.case.fill", "pills.fill", "stethoscope", "figure.run", "dumbbell.fill", "sportscourt.fill", "music.note", "gamecontroller.fill", "camera.fill",
        "photo.fill", "film.fill", "headphones", "tshirt.fill", "pawprint.fill", "graduationcap.fill", "atom", "shield.fill", "lifepreserver.fill",
    ]

    // MARK: Load and save

    private func load() {
        defer { DispatchQueue.main.async { didLoad = true } }
        switch target {
        case .group(let id):
            guard let group = store.group(id) else { return }
            name = group.name
            symbol = group.symbol
            colorValue = group.colorValue
        case .snippet(let id):
            guard let snippet = store.snippet(id) else { return }
            name = snippet.trigger
            symbol = snippet.symbol
            colorValue = snippet.color
            groupID = snippet.groupID
            text = snippet.expansion
            notes = snippet.notes
        case .newGroup:
            symbol = "folder.fill"
            colorValue = GroupColor.blue.rawValue
        case .newSnippet(let id):
            groupID = id
        }
        if let color = QuillColor.resolve(colorValue), colorValue?.hasPrefix("#") == true { customColor = color }
        isNameFocused = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .group(let id):
            store.updateGroup(id) { apply(to: &$0, name: trimmed) }
        case .newGroup:
            let group = store.addGroup(named: trimmed)
            store.updateGroup(group.id) { apply(to: &$0, name: trimmed) }
        case .snippet(let id):
            store.update(id) { apply(to: &$0, trigger: trimmed) }
        case .newSnippet:
            let snippet = store.add(trigger: trimmed, groupID: groupID)
            store.update(snippet.id) { apply(to: &$0, trigger: trimmed) }
            if let groupID { store.updateGroup(groupID) { $0.isExpanded = true } }
            state.selection = [.snippet(snippet.id)]
        }
        dismiss()
    }

    private func apply(to group: inout SnippetGroup, name: String) {
        group.name = name
        group.symbol = symbol ?? "folder.fill"
        if let value = colorValue, let system = GroupColor(rawValue: value) {
            group.color = system
            group.customColor = nil
        } else if let value = colorValue {
            group.customColor = value
        }
    }

    private func apply(to snippet: inout Snippet, trigger: String) {
        snippet.trigger = trigger
        snippet.symbol = symbol
        snippet.color = colorValue
        snippet.groupID = groupID
        snippet.expansion = text
        snippet.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Pieces

/// The big preview tile: the icon on its colour.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 56

    var body: some View {
        Group {
            if IconKind.isEmoji(symbol) {
                Text(symbol).font(.system(size: size * 0.55))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(color, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct Swatch: View {
    let color: Color
    let title: String
    let isSelected: Bool
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .padding(4)
                .overlay {
                    Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

