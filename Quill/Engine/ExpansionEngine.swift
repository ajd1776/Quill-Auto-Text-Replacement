import AppKit
import CoreGraphics

/// Watches keystrokes system-wide through a Quartz event tap, suggests snippets as you
/// type and expands matching shortcuts.
///
/// Needs Accessibility access. macOS never delivers keystrokes from secure fields
/// (password boxes) to event taps, so those are skipped automatically.
@MainActor
final class ExpansionEngine {
    static let shared = ExpansionEngine()

    struct Expansion {
        let snippet: Snippet
        let style: ReplacementAnimation
        /// The text actually typed, with tokens filled in.
        let renderedText: String
    }

    /// A snippet the bubble offers while you type. `typedCount` characters of its shortcut are already typed.
    struct Suggestion: Equatable, Identifiable {
        let snippet: Snippet
        let typedCount: Int
        var id: Snippet.ID { snippet.id }
        var isExact: Bool { typedCount == snippet.trigger.count }
    }

    /// What the last expansion inserted, so Delete straight afterwards can undo it.
    private struct LastExpansion {
        let snippetID: Snippet.ID
        let insertedCount: Int
        let restore: String
    }

    private(set) var isRunning = false
    var isPaused = false { didSet { reset() } }
    /// Set while Quill's own search panel has focus.
    var isSuspended = false { didSet { reset() } }
    /// Quill's own windows are skipped, except where this says typing is practice
    /// (the Firing Range's practice text).
    var listensInQuill: () -> Bool = { false }
    var excludedBundleIDs = Set<String>()
    var typewriterSpeed: Double = 60
    /// When false, animations play even with Reduce Motion on (the person's explicit choice).
    var honoursReduceMotion = true
    var suggestionsEnabled = true { didSet { clearSuggestions() } }
    /// When false, the space typed to trigger a snippet is dropped, so the text ends right after
    /// the snippet. Return, Tab and punctuation always go through.
    var keepsTriggerSpace = true
    /// Set by the bubble. Tab, Esc and ↑↓ only act on suggestions while the bubble is on screen,
    /// so a bubble that couldn't be shown never swallows those keys.
    var isBubbleVisible = false
    var partialSuggestionsEnabled = true { didSet { clearSuggestions() } }
    var styleResolver: (Snippet) -> ReplacementAnimation = { $0.animation ?? .instant }
    var onExpanded: ((Expansion) -> Void)?
    var onUndone: ((Snippet.ID) -> Void)?
    /// Called with the current suggestions and the highlighted index; an empty list hides the bubble.
    var onSuggestionsChanged: (([Suggestion], Int) -> Void)?
    /// Asks for fill-in values ({input:Label}). The completion gets the values, or nil if cancelled.
    var onNeedsInput: ((Snippet, [String], @escaping ([String: String]?) -> Void) -> Void)?
    /// True while the fill-in form is open, so typing into it isn't treated as shortcuts.
    private(set) var isAwaitingInput = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObserver: NSObjectProtocol?
    private var frontmostBundleID: String?

    /// The characters typed since the insertion point last moved.
    private var buffer = ""
    private let maxBufferLength = 128
    private var lastExpansion: LastExpansion?

    private var activeSnippets: [Snippet] = []
    private var delimiterSnippets: [Snippet] = []
    private var immediateSnippets: [Snippet] = []
    private let emitter = KeyboardEmitter()

    private var suggestions: [Suggestion] = []
    private var highlighted = 0
    /// The buffer at the moment Esc dismissed the bubble; the shortcut won't expand until you type on.
    private var dismissedBuffer: String?
    private let minimumPrefixLength = 2
    private let maxSuggestions = 5

    private static let delimiters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

    // MARK: Configuration

    /// Pass only snippets that should fire: enabled, valid and in an enabled group.
    func update(snippets: [Snippet]) {
        // Longest first, so "eADx" wins over "eAD" when both could match. A snippet with
        // no text would just delete the shortcut, so it's skipped.
        activeSnippets = snippets
            .filter { $0.isEnabled && $0.hasValidTrigger && !$0.expansion.isEmpty }
            .sorted { $0.trigger.count > $1.trigger.count }
        delimiterSnippets = activeSnippets.filter { $0.mode == .afterDelimiter }
        immediateSnippets = activeSnippets.filter { $0.mode == .immediate }
        clearSuggestions()
    }

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: quillEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source

        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontmostBundleID = app?.bundleIdentifier
                self?.reset()
            }
        }

        isRunning = true
        return true
    }

    func stop() {
        emitter.finishTyping()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        tap = nil
        runLoopSource = nil
        workspaceObserver = nil
        reset()
        isRunning = false
    }

    /// Inserts a snippet at the cursor without typing its shortcut, for the search panel and menu bar.
    /// Puts the quill's text where the cursor is. `pasting` uses the clipboard (put back afterwards)
    /// instead of typing it, as the menu bar panel does: instant and the same in every app.
    func insert(_ snippet: Snippet, pasting: Bool = false) {
        emitter.finishTyping()
        reset()
        isPasting = pasting
        expand(snippet, deleting: 0, replay: nil, typed: "", allowsUndo: true)
    }

    /// The current insert pastes instead of typing.
    private var isPasting = false

    // MARK: Event handling

    #if DEBUG
    /// Lets the self-test drive the engine while Quill itself is frontmost.
    var isSelfTesting = false
    func setFrontmostForTesting(_ bundleID: String?) { frontmostBundleID = bundleID }
    #endif

    private var shouldExpand: Bool {
        #if DEBUG
        if isSelfTesting { return !isPaused && !isAwaitingInput }
        #endif
        if isPaused || isSuspended || isAwaitingInput { return false }
        if NSApp.isActive, !listensInQuill() { return false }
        if let frontmostBundleID, excludedBundleIDs.contains(frontmostBundleID) { return false }
        return true
    }

    private func reset() {
        buffer = ""
        lastExpansion = nil
        dismissedBuffer = nil
        clearSuggestions()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            if event.getIntegerValueField(.eventSourceUserData) == KeyboardEmitter.marker {
                return Unmanaged.passUnretained(event)
            }
            // A click can move the insertion point anywhere. If the typewriter is
            // still going, finish the text first so the click lands after it.
            reset()
            if emitter.finishTyping() { return emitter.repost(event) }
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardEmitter.marker {
            return Unmanaged.passUnretained(event)
        }

        // A key pressed mid-typewriter finishes the text first, so nothing interleaves.
        let interruptedTyping = emitter.finishTyping()
        let pass = { () -> Unmanaged<CGEvent>? in
            interruptedTyping ? self.emitter.repost(event) : Unmanaged.passUnretained(event)
        }

        guard shouldExpand else {
            if !buffer.isEmpty || !suggestions.isEmpty {
                quillLog.debug("Engine: not listening (paused \(self.isPaused, privacy: .public), suspended \(self.isSuspended, privacy: .public), Quill frontmost \(NSApp.isActive, privacy: .public), app paused \(self.frontmostBundleID.map(self.excludedBundleIDs.contains) ?? false, privacy: .public))")
            }
            reset()
            return pass()
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasCommandKeys = flags.contains(.maskCommand) || flags.contains(.maskControl)
        let hasModifiers = hasCommandKeys || flags.contains(.maskAlternate) || flags.contains(.maskShift)

        // The suggestion bubble's keys: Esc dismisses, Tab accepts, ↑↓ choose.
        if !suggestions.isEmpty, isBubbleVisible, !hasModifiers {
            switch keyCode {
            case KeyCode.escape:
                dismissedBuffer = buffer
                clearSuggestions()
                return nil
            case KeyCode.tab:
                let suggestion = suggestions[min(highlighted, suggestions.count - 1)]
                let typed = String(buffer.suffix(suggestion.typedCount))
                buffer = ""
                expand(suggestion.snippet, deleting: suggestion.typedCount, replay: nil, typed: typed, allowsUndo: true)
                return nil
            case KeyCode.downArrow where suggestions.count > 1:
                highlighted = (highlighted + 1) % suggestions.count
                publishSuggestions()
                return nil
            case KeyCode.upArrow where suggestions.count > 1:
                highlighted = (highlighted - 1 + suggestions.count) % suggestions.count
                publishSuggestions()
                return nil
            default:
                break
            }
        }

        // Delete straight after an expansion puts the shortcut back.
        if let last = lastExpansion {
            lastExpansion = nil
            if keyCode == KeyCode.delete, !hasCommandKeys, !flags.contains(.maskAlternate) {
                undo(last)
                return nil
            }
        }

        if hasCommandKeys {
            reset()
            return pass()
        }
        if keyCode == KeyCode.delete {
            if !buffer.isEmpty { buffer.removeLast() }
            dismissedBuffer = nil
            refreshSuggestions()
            return pass()
        }
        if KeyCode.navigation.contains(keyCode) {
            reset()
            return pass()
        }

        let isLineOrTab = keyCode == KeyCode.returnKey || keyCode == KeyCode.enter || keyCode == KeyCode.tab
        let typed: String
        if isLineOrTab {
            typed = "\n"
        } else {
            guard let characters = event.typedCharacters, !characters.isEmpty else { return pass() }
            if characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                reset()
                return pass()
            }
            typed = characters
        }

        // 1. A delimiter completes an after-delimiter shortcut already in the buffer,
        //    unless the bubble for it was just dismissed with Esc.
        let isDelimiter = typed.unicodeScalars.allSatisfy { Self.delimiters.contains($0) }
        if isDelimiter, dismissedBuffer != buffer, let (snippet, typedShortcut) = match(in: delimiterSnippets) {
            buffer = ""
            clearSuggestions()
            // Return and Tab can send a message or move focus, so they can't be undone.
            // The trigger space is dropped when that's turned off; Return and Tab never are.
            let dropsSpace = !keepsTriggerSpace && typed == " "
            expand(snippet, deleting: typedShortcut.count, replay: dropsSpace ? nil : event,
                   typed: typedShortcut, allowsUndo: !isLineOrTab)
            return nil
        }

        if isLineOrTab {
            reset()
            return pass()
        }

        buffer.append(typed)
        if buffer.count > maxBufferLength {
            buffer.removeFirst(buffer.count - maxBufferLength)
        }
        dismissedBuffer = nil

        // 2. This keystroke finishes an immediate shortcut. The key hasn't reached the
        //    app yet, so delete one character fewer than the shortcut's length.
        if let (snippet, typedShortcut) = match(in: immediateSnippets) {
            buffer = ""
            clearSuggestions()
            expand(snippet, deleting: typedShortcut.count - 1, replay: nil,
                   typed: typedShortcut, allowsUndo: true)
            return nil
        }

        refreshSuggestions()
        return pass()
    }

    // MARK: Expanding

    /// Replaces `count` typed characters with the snippet. `typed` is exactly what was typed
    /// (for case matching and for putting back on undo or cancel).
    private func expand(_ snippet: Snippet, deleting count: Int, replay: CGEvent?, typed: String, allowsUndo: Bool) {
        let fields = TokenRenderer.inputFields(in: snippet.expansion)
        guard !fields.isEmpty, let onNeedsInput else {
            emitter.deleteBackward(count)
            emit(snippet, inputs: [:], replay: replay, typed: typed, allowsUndo: allowsUndo)
            return
        }

        // Fill-in fields: remove the shortcut, ask for the values, then type the result.
        emitter.deleteBackward(count)
        lastExpansion = nil
        isAwaitingInput = true
        clearSuggestions()
        onNeedsInput(snippet, fields) { [weak self] values in
            guard let self else { return }
            self.isAwaitingInput = false
            self.buffer = ""
            guard let values else {
                // Cancelled: put back what was typed.
                if !typed.isEmpty { self.emitter.insert(typed) }
                return
            }
            self.emit(snippet, inputs: values, replay: nil, typed: typed, allowsUndo: true)
        }
    }

    private func emit(_ snippet: Snippet, inputs: [String: String], replay: CGEvent?, typed: String, allowsUndo: Bool) {
        var style = styleResolver(snippet)
        if honoursReduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !style.survivesReduceMotion {
            style = .instant
        }

        var rendered = TokenRenderer.render(snippet.expansion.replacingOccurrences(of: "\r\n", with: "\n"), inputs: inputs)
        if snippet.matchesAnyCase, !typed.isEmpty {
            let typedPart = String(typed.suffix(snippet.trigger.count))
            rendered.text = CaseAdapter.adapt(rendered.text, typed: typedPart, trigger: String(snippet.trigger.prefix(typedPart.count)))
        }
        let movesCursor = (rendered.cursorBack ?? 0) > 0
        // With {cursor}, the cursor lands inside the text, so the delimiter isn't typed after it.
        let replay = movesCursor ? nil : replay

        let pastes = isPasting
        isPasting = false
        if pastes {
            emitter.insert(rendered.text, pasting: true)
            emitter.moveLeft(rendered.cursorBack ?? 0)
        } else if style == .typewriter {
            emitter.typewrite(rendered.text, charactersPerSecond: typewriterSpeed,
                              thenReplay: replay, thenMoveLeft: rendered.cursorBack ?? 0)
        } else {
            emitter.insert(rendered.text)
            emitter.moveLeft(rendered.cursorBack ?? 0)
            if let replay { emitter.replay(replay) }
        }

        let inserted = rendered.text.count + (replay == nil ? 0 : 1)
        lastExpansion = allowsUndo && !movesCursor
            ? LastExpansion(snippetID: snippet.id, insertedCount: inserted, restore: typed)
            : nil
        onExpanded?(Expansion(snippet: snippet, style: style, renderedText: rendered.text))
    }

    private func undo(_ last: LastExpansion) {
        emitter.deleteBackward(last.insertedCount)
        if !last.restore.isEmpty { emitter.insert(last.restore) }
        // The restored shortcut isn't in the buffer, so it won't expand again straight away.
        buffer = ""
        clearSuggestions()
        onUndone?(last.snippetID)
    }

    /// Finds a snippet whose shortcut ends the buffer as a whole word, in an app it's allowed in.
    /// Returns the snippet and exactly what was typed.
    private func match(in snippets: [Snippet]) -> (Snippet, String)? {
        for snippet in snippets where snippet.isAllowed(in: frontmostBundleID) {
            let length = snippet.trigger.count
            guard buffer.count >= length else { continue }
            let typed = String(buffer.suffix(length))
            if Self.shortcut(typed, matches: snippet.trigger, anyCase: snippet.matchesAnyCase),
               isAtWordStart(beforeCount: length, trigger: snippet.trigger) {
                return (snippet, typed)
            }
        }
        return nil
    }

    private static func shortcut(_ typed: String, matches trigger: String, anyCase: Bool) -> Bool {
        anyCase ? typed.caseInsensitiveCompare(trigger) == .orderedSame : typed == trigger
    }

    /// A shortcut that starts with a letter or digit only counts when the character
    /// before it isn't one, so "eAD" never fires inside "readeAD".
    private func isAtWordStart(beforeCount count: Int, trigger: String) -> Bool {
        guard let first = trigger.first, first.isLetter || first.isNumber else { return true }
        guard let previous = buffer.dropLast(count).last else { return true }
        return !(previous.isLetter || previous.isNumber)
    }

    // MARK: Suggestions

    private func refreshSuggestions() {
        let previousIDs = suggestions.map(\.id)
        let previousHighlight = suggestions.indices.contains(highlighted) ? suggestions[highlighted].id : nil
        suggestions = computeSuggestions()
        if suggestions.map(\.id) != previousIDs {
            highlighted = previousHighlight.flatMap { id in suggestions.firstIndex { $0.id == id } } ?? 0
        }
        publishSuggestions()
    }

    private func computeSuggestions() -> [Suggestion] {
        guard suggestionsEnabled, !buffer.isEmpty, dismissedBuffer != buffer else { return [] }
        var found: [Suggestion] = []
        for snippet in activeSnippets where snippet.isAllowed(in: frontmostBundleID) {
            let trigger = snippet.trigger
            let anyCase = snippet.matchesAnyCase
            func ends(with part: Substring) -> Bool {
                buffer.count >= part.count && Self.shortcut(String(buffer.suffix(part.count)), matches: String(part), anyCase: anyCase)
            }
            if snippet.mode == .afterDelimiter, ends(with: Substring(trigger)),
               isAtWordStart(beforeCount: trigger.count, trigger: trigger) {
                found.append(Suggestion(snippet: snippet, typedCount: trigger.count))
                continue
            }
            guard partialSuggestionsEnabled, trigger.count > minimumPrefixLength else { continue }
            for length in stride(from: trigger.count - 1, through: minimumPrefixLength, by: -1) {
                if ends(with: trigger.prefix(length)), isAtWordStart(beforeCount: length, trigger: trigger) {
                    found.append(Suggestion(snippet: snippet, typedCount: length))
                    break
                }
            }
        }
        found.sort { lhs, rhs in
            if lhs.isExact != rhs.isExact { return lhs.isExact }
            if lhs.typedCount != rhs.typedCount { return lhs.typedCount > rhs.typedCount }
            if lhs.snippet.useCount != rhs.snippet.useCount { return lhs.snippet.useCount > rhs.snippet.useCount }
            return lhs.snippet.trigger.localizedStandardCompare(rhs.snippet.trigger) == .orderedAscending
        }
        return Array(found.prefix(maxSuggestions))
    }

    private func clearSuggestions() {
        guard !suggestions.isEmpty else { return }
        suggestions = []
        highlighted = 0
        publishSuggestions()
    }

    private func publishSuggestions() {
        quillLog.debug("Engine: \(self.suggestions.count, privacy: .public) suggestions, buffer \(self.buffer.count, privacy: .public) chars, \(self.activeSnippets.count, privacy: .public) active snippets")
        onSuggestionsChanged?(suggestions, highlighted)
    }
}

private func quillEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ExpansionEngine>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap's run loop source is on the main run loop, so this always runs on the main thread.
    return MainActor.assumeIsolated {
        engine.handle(type: type, event: event)
    }
}
