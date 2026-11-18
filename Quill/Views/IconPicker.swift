import SwiftUI

/// Pick an SF Symbol or any emoji as a group or snippet icon.
struct IconPicker: View {
    let current: String?
    let tint: Color
    /// Shown as a first option that clears the icon, for example "Use Group Icon".
    var defaultTitle: String?
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var search = ""
    @State private var typedEmoji = ""
    @FocusState private var isEmojiFieldFocused: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case symbols = "Symbols"
        case emoji = "Emoji"
        var id: String { rawValue }
    }

    init(current: String?, tint: Color, defaultTitle: String? = nil, onPick: @escaping (String?) -> Void) {
        self.current = current
        self.tint = tint
        self.defaultTitle = defaultTitle
        self.onPick = onPick
        _tab = State(initialValue: current.map(IconKind.isEmoji) == true ? .emoji : .symbols)
    }

    private var symbols: [(name: String, keywords: String)] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Self.symbolCatalog }
        return Self.symbolCatalog.filter { $0.name.contains(query) || $0.keywords.contains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Icon type", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Spacer()
                if let defaultTitle {
                    Button(defaultTitle) { choose(nil) }
                        .controlSize(.small)
                }
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }

            if tab == .symbols {
                TextField("Search symbols", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 8), spacing: 6) {
                        ForEach(symbols, id: \.name) { symbol in
                            IconCell(isSelected: current == symbol.name, tint: tint) {
                                Image(systemName: symbol.name)
                                    .font(.system(size: 17, weight: .medium))
                            } action: { choose(symbol.name) }
                            .help(symbol.keywords.capitalized)
                        }
                    }
                    .padding(2)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("Type or paste any emoji", text: $typedEmoji)
                        .textFieldStyle(.roundedBorder)
                        .focused($isEmojiFieldFocused)
                        .onChange(of: typedEmoji) { _, value in
                            if let last = value.last.map(String.init), IconKind.isEmoji(last) { choose(last) }
                        }
                    Button("Emoji & Symbols", systemImage: "face.smiling") {
                        isEmojiFieldFocused = true
                        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                    }
                    .help("Open the macOS emoji picker")
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 8), spacing: 6) {
                        ForEach(Self.emojiCatalog, id: \.self) { emoji in
                            IconCell(isSelected: current == emoji, tint: tint) {
                                Text(emoji).font(.system(size: 22))
                            } action: { choose(emoji) }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(16)
        .frame(width: 392, height: 420)
    }

    private func choose(_ icon: String?) {
        onPick(icon)
        dismiss()
    }

    // MARK: Catalogues

    static let symbolCatalog: [(name: String, keywords: String)] = [
        ("folder.fill", "folder"), ("tray.full.fill", "tray inbox"), ("archivebox.fill", "archive box"),
        ("person.fill", "person me"), ("person.2.fill", "people team"), ("person.crop.circle.fill", "profile account"),
        ("envelope.fill", "email mail"), ("paperplane.fill", "send"), ("bubble.left.fill", "message chat"),
        ("phone.fill", "phone call"), ("video.fill", "video call"), ("at", "at email"),
        ("house.fill", "home address"), ("building.2.fill", "office work"), ("briefcase.fill", "work job"),
        ("mappin.and.ellipse", "address location"), ("map.fill", "map"), ("car.fill", "car travel"),
        ("airplane", "flight travel"), ("cart.fill", "cart shop"), ("bag.fill", "bag shop store"),
        ("creditcard.fill", "card payment"), ("banknote.fill", "money cash"), ("sterlingsign.circle.fill", "pound money"),
        ("shippingbox.fill", "box order shipping"), ("tag.fill", "tag label price"), ("gift.fill", "gift"),
        ("calendar", "calendar date"), ("clock.fill", "time clock"), ("alarm.fill", "alarm"),
        ("doc.text.fill", "document text"), ("note.text", "note"), ("list.bullet", "list"),
        ("checklist", "checklist todo"), ("checkmark.seal.fill", "approved check"), ("signature", "signature"),
        ("text.quote", "quote text"), ("textformat", "text format"), ("character.cursor.ibeam", "cursor typing"),
        ("link", "link url"), ("globe", "web internet"), ("wifi", "wifi network"),
        ("chevron.left.forwardslash.chevron.right", "code html"), ("terminal.fill", "terminal shell"), ("curlybraces", "code braces"),
        ("number", "number hash"), ("key.fill", "key password"), ("lock.fill", "lock secure"),
        ("star.fill", "star favourite"), ("heart.fill", "heart love"), ("bolt.fill", "bolt fast"),
        ("sparkles", "sparkles magic"), ("wand.and.stars", "magic wand"), ("flame.fill", "fire hot"),
        ("lightbulb.fill", "idea bulb"), ("bookmark.fill", "bookmark"), ("flag.fill", "flag"),
        ("bell.fill", "bell notification"), ("hand.wave.fill", "wave hello"), ("hand.thumbsup.fill", "thumbs up"),
        ("face.smiling", "smile face"), ("graduationcap.fill", "school education"), ("book.fill", "book"),
        ("music.note", "music"), ("camera.fill", "camera photo"), ("photo.fill", "photo image"),
        ("paintbrush.fill", "paint design"), ("pencil", "pencil edit"), ("scissors", "cut scissors"),
        ("hammer.fill", "tools build"), ("wrench.and.screwdriver.fill", "tools fix"), ("gearshape.fill", "settings gear"),
        ("cup.and.saucer.fill", "coffee tea"), ("fork.knife", "food restaurant"), ("leaf.fill", "leaf nature"),
        ("pawprint.fill", "pet animal"), ("sun.max.fill", "sun weather"), ("moon.fill", "moon night"),
        ("cross.case.fill", "medical health"), ("heart.text.square.fill", "health"), ("figure.run", "run sport"),
        ("gamecontroller.fill", "game"), ("trophy.fill", "trophy win"), ("crown.fill", "crown king"),
    ]

    static let emojiCatalog: [String] = [
        "😀", "😄", "😂", "😊", "😍", "😎", "🤔", "😴", "🥳", "🤓", "😇", "🙃",
        "👋", "👍", "👏", "🙏", "💪", "✌️", "🤝", "👀", "🧠", "❤️", "💜", "💙",
        "🔥", "✨", "⭐️", "⚡️", "🌈", "☀️", "🌙", "❄️", "🌊", "🍀", "🌸", "🌵",
        "🎉", "🎁", "🎯", "🏆", "🚀", "💡", "📌", "📎", "✏️", "🖊️", "📝", "📅",
        "📧", "💬", "📞", "📱", "💻", "⌨️", "🖥️", "🔒", "🔑", "🛠️", "⚙️", "🧪",
        "📦", "🚚", "🛒", "🛍️", "💳", "💰", "🏷️", "🧾", "🏠", "🏢", "✈️", "🚗",
        "☕️", "🍕", "🍔", "🍎", "🍺", "🎵", "🎨", "📷", "🎮", "⚽️", "🏃", "🐶",
        "🐱", "🦄", "🐝", "🌍", "🇬🇧", "✅", "❌", "⚠️", "❓", "💯", "🔗", "🧩",
    ]
}

private struct IconCell<Content: View>: View {
    let isSelected: Bool
    let tint: Color
    @ViewBuilder let content: Content
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content
                .frame(width: 40, height: 40)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(
                    isSelected ? AnyShapeStyle(tint.gradient) : (isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear)),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
