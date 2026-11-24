import AppIntents
import Foundation

// Actions for Apple's Shortcuts app and Spotlight.

struct SnippetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quill"
    static let defaultQuery = SnippetQuery()

    let id: UUID
    let trigger: String
    let preview: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(trigger)", subtitle: "\(preview)")
    }

    init(_ snippet: Snippet) {
        id = snippet.id
        trigger = snippet.trigger
        preview = String(snippet.preview.prefix(60))
    }
}

struct SnippetQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetEntity] {
        identifiers.compactMap { AppState.shared.store.snippet($0) }.map(SnippetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        AppState.shared.store.snippets
            .filter { $0.hasValidTrigger && ($0.trigger.localizedCaseInsensitiveContains(string) || $0.expansion.localizedCaseInsensitiveContains(string)) }
            .map(SnippetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        AppState.shared.store.snippets
            .filter(\.hasValidTrigger)
            .sorted(by: SnippetSortOrder.mostUsed.areInIncreasingOrder)
            .map(SnippetEntity.init)
    }
}

enum QuillPower: String, AppEnum {
    case on, off, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Quill State"
    static let caseDisplayRepresentations: [QuillPower: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .toggle: "Toggle",
    ]
}

struct SetQuillIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Quill On or Off"
    static let description = IntentDescription("Turns quill expansion on, off, or toggles it.")

    @Parameter(title: "Turn", default: .toggle)
    var state: QuillPower

    static var parameterSummary: some ParameterSummary {
        Summary("Turn Quill \(\.$state)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let app = AppState.shared
        switch state {
        case .on: app.setOn(true, announce: true)
        case .off: app.setOn(false, announce: true)
        case .toggle: app.setOn(!app.isOn, announce: true)
        }
        return .result(value: app.isOn)
    }
}

struct GetSnippetTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Quill Text"
    static let description = IntentDescription("Returns a quill's text, with date, time and clipboard tokens filled in.")

    @Parameter(title: "Quill")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the text of \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let stored = AppState.shared.store.snippet(snippet.id) else {
            throw QuillIntentError.snippetMissing
        }
        return .result(value: TokenRenderer.render(stored.expansion).text)
    }
}

struct InsertSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Insert Quill"
    static let description = IntentDescription("Types a quill into the app you're using, as if you'd typed its shortcut.")

    @Parameter(title: "Quill")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Insert \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let stored = AppState.shared.store.snippet(snippet.id) else {
            throw QuillIntentError.snippetMissing
        }
        AppState.shared.insert(stored, after: 0.3)
        return .result()
    }
}

struct AddSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Quill"
    static let description = IntentDescription("Creates a new quill in Quill.")

    @Parameter(title: "Shortcut")
    var shortcut: String

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add quill \(\.$shortcut) that types \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SnippetEntity> {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { throw QuillIntentError.badShortcut }
        guard !AppState.shared.store.containsTrigger(trimmed) else { throw QuillIntentError.shortcutTaken(trimmed) }
        let snippet = AppState.shared.store.add(trigger: trimmed, expansion: text)
        return .result(value: SnippetEntity(snippet))
    }
}

enum QuillIntentError: Error, CustomLocalizedStringResourceConvertible {
    case snippetMissing
    case badShortcut
    case shortcutTaken(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .snippetMissing: "That quill no longer exists in Quill."
        case .badShortcut: "A shortcut can't be empty or contain spaces."
        case .shortcutTaken(let shortcut): "Another quill already uses \(shortcut)."
        }
    }
}

struct QuillShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetQuillIntent(),
            phrases: ["Toggle \(.applicationName)", "Turn \(.applicationName) on or off"],
            shortTitle: "Turn Quill On or Off",
            systemImageName: "pencil.line"
        )
        AppShortcut(
            intent: InsertSnippetIntent(),
            phrases: ["Insert a quill with \(.applicationName)"],
            shortTitle: "Insert Quill",
            systemImageName: "text.insert"
        )
    }
}
