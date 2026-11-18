import AppKit
import CoreGraphics

/// Posts synthetic key events: backspaces to remove a shortcut, then the expansion text,
/// either all at once or typewriter-style, one character at a time.
@MainActor
final class KeyboardEmitter {
    /// Stamped on every event Quill posts, so the engine ignores its own typing.
    static let marker: Int64 = 0x5155_494C // "QUIL"

    /// Expansions longer than this are pasted instead of typed, which is faster and more reliable.
    private let pasteThreshold = 160
    /// The typewriter never takes longer than this, however long the snippet.
    private let maxTypewriterDuration = 3.0
    private let source = CGEventSource(stateID: .privateState)

    private enum Step {
        case characters([UniChar])
        case key(CGKeyCode)
        case event(CGEvent)
    }

    private var pending: [Step] = []
    private var typingTask: Task<Void, Never>?
    private var generation = 0

    var isTyping: Bool { typingTask != nil }

    // MARK: Instant

    func deleteBackward(_ count: Int) {
        for _ in 0..<max(0, count) {
            tap(keyCode: CGKeyCode(KeyCode.delete))
        }
    }

    func insert(_ text: String) {
        if text.count > pasteThreshold {
            paste(text)
        } else {
            steps(for: text, oneCharacterEach: false).forEach(post)
        }
    }

    /// Moves the cursor left, for snippets that contain {cursor}.
    func moveLeft(_ count: Int) {
        for _ in 0..<max(0, count) {
            tap(keyCode: CGKeyCode(KeyCode.leftArrow))
        }
    }

    /// Posts a copy of a key the person pressed, after Quill's own events.
    func replay(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        mark(copy)
        send(copy)
    }

    /// Swallows an event and posts it again, so it lands after anything Quill has queued.
    func repost(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        replay(event)
        return nil
    }

    // MARK: Typewriter

    func typewrite(_ text: String, charactersPerSecond: Double, thenReplay replay: CGEvent?, thenMoveLeft moveLeft: Int = 0) {
        finishTyping()

        var steps = steps(for: text, oneCharacterEach: true)
        steps.append(contentsOf: Array(repeating: Step.key(CGKeyCode(KeyCode.leftArrow)), count: max(0, moveLeft)))
        if let replay, let copy = replay.copy() {
            mark(copy)
            steps.append(.event(copy))
        }
        guard !steps.isEmpty else { return }

        let interval = min(1 / max(charactersPerSecond, 1), maxTypewriterDuration / Double(steps.count))
        pending = steps
        generation += 1
        let token = generation

        typingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token, !self.pending.isEmpty else { break }
                self.post(self.pending.removeFirst())
                try? await Task.sleep(for: .seconds(interval))
            }
            if let self, self.generation == token { self.typingTask = nil }
        }
    }

    /// Types whatever the typewriter hasn't typed yet, straight away.
    /// Returns true if it was typing, so the caller can repost the event that interrupted it.
    @discardableResult
    func finishTyping() -> Bool {
        guard typingTask != nil else { return false }
        generation += 1
        typingTask?.cancel()
        typingTask = nil
        let remaining = pending
        pending.removeAll()
        remaining.forEach(post)
        return true
    }

    // MARK: Posting

    private func steps(for text: String, oneCharacterEach: Bool) -> [Step] {
        var result: [Step] = []
        var run: [UniChar] = []

        func flush() {
            if !run.isEmpty {
                result.append(.characters(run))
                run.removeAll(keepingCapacity: true)
            }
        }

        for character in text {
            if character.isNewline {
                flush()
                result.append(.key(CGKeyCode(KeyCode.returnKey)))
                continue
            }
            let units = Array(String(character).utf16)
            // Key events carry at most 20 UTF-16 units; never split a character across two.
            if oneCharacterEach || run.count + units.count > 20 { flush() }
            run.append(contentsOf: units)
        }
        flush()
        return result
    }

    private func post(_ step: Step) {
        switch step {
        case .characters(let units): postUnicode(units)
        case .key(let keyCode): tap(keyCode: keyCode)
        case .event(let event): send(event)
        }
    }

    #if DEBUG
    /// When set, events go here instead of to the system. Used by the engine self-test.
    static var recorder: ((CGEvent) -> Void)?
    #endif

    private func send(_ event: CGEvent) {
        #if DEBUG
        if let recorder = Self.recorder {
            recorder(event)
            return
        }
        #endif
        event.post(tap: .cghidEventTap)
    }

    private func postUnicode(_ units: [UniChar]) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
            event.flags = []
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            mark(event)
            send(event)
        }
    }

    private func tap(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            mark(event)
            send(event)
        }
    }

    private func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
    }

    // MARK: Pasting

    /// Pastes the text with Command-V, then puts the previous clipboard contents back.
    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount

        tap(keyCode: KeyCode.v, flags: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Leave the clipboard alone if something else changed it meanwhile.
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            let items = saved.map { contents -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in contents { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
    }
}
