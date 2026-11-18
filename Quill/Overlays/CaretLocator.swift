import AppKit
import ApplicationServices
import os

let quillLog = Logger(subsystem: "dev.quill.Quill", category: "diagnostics")

/// What a cursor lookup needs from the main thread, captured up front so the lookup itself
/// can run on a background queue and never stall typing.
struct ScreenSnapshot: Sendable {
    let primaryMaxY: CGFloat
    let screens: [CGRect]
    let bundleID: String
    let pid: pid_t?

    @MainActor
    static func current() -> ScreenSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        return ScreenSnapshot(
            primaryMaxY: NSScreen.screens.first?.frame.maxY ?? 0,
            screens: NSScreen.screens.map(\.frame),
            bundleID: app?.bundleIdentifier ?? "unknown",
            pid: app?.processIdentifier
        )
    }
}

/// Finds the text cursor, and the text just before it, in the frontmost app through the
/// Accessibility API. Rectangles are in AppKit screen coordinates (origin bottom-left).
///
/// Accessibility calls go to another process and can take a while, so lookups run on a
/// private queue; `lookup` hands the result back on the main thread.
enum CaretLocator {
    struct Geometry: Sendable {
        /// The cursor.
        var caret: CGRect
        /// The last line of the text just inserted, ending at the cursor.
        var line: CGRect
    }

    private static let queue = DispatchQueue(label: "dev.quill.Quill.caret", qos: .userInteractive)
    /// Each AX call may wait this long for an unresponsive app.
    private static let timeout: Float = 0.12
    /// Log keys already written and Electron apps already asked, so neither repeats every keystroke.
    private static let seen = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Runs `work` off the main thread with a snapshot of the screens and frontmost app,
    /// then calls `completion` on the main thread.
    @MainActor
    static func lookup<Result>(_ work: @escaping @Sendable (ScreenSnapshot) -> Result,
                               completion: @escaping @MainActor (Result) -> Void) {
        let snapshot = ScreenSnapshot.current()
        queue.async {
            let result = work(snapshot)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(result) }
            }
        }
    }

    // MARK: Queries (run on the lookup queue)

    /// The cursor, or with `fieldFallback` the bottom-left of the focused text field when an app won't say.
    static func caret(_ snapshot: ScreenSnapshot, fieldFallback: Bool) -> CGRect? {
        guard let element = focusedElement(snapshot) else { return nil }
        if let location = selectionLocation(element, snapshot),
           let caret = rangeCaret(element, at: location, snapshot) {
            return caret
        }
        // Chromium and Electron apps (Chrome, Claude, Slack, VS Code) report the cursor through text markers instead.
        if let caret = markerCaret(element, snapshot) { return caret }
        return fieldFallback ? fieldRect(element, snapshot) : nil
    }

    /// The cursor plus, when the app can measure it, the rectangle of the `lineLength` characters before it.
    /// A nil line means the caller should estimate it from the font size.
    static func geometry(_ snapshot: ScreenSnapshot, lineLength: Int) -> (caret: CGRect, line: CGRect?)? {
        guard let element = focusedElement(snapshot) else { return nil }
        if let location = selectionLocation(element, snapshot),
           let caret = rangeCaret(element, at: location, snapshot) {
            if lineLength > 0, location >= lineLength,
               let raw = bounds(element, range: CFRange(location: location - lineLength, length: lineLength)),
               let line = toAppKit(raw, snapshot), line.height > 1, line.height < caret.height * 1.8 {
                return (caret, line)
            }
            return (caret, nil)
        }
        if let caret = markerCaret(element, snapshot) { return (caret, nil) }
        return nil
    }

    /// Estimates where a line of text ending at the cursor sits. Call on the main thread.
    @MainActor
    static func estimatedLine(endingAt caret: CGRect, text: String) -> CGRect {
        let font = NSFont.systemFont(ofSize: max(10, caret.height * 0.78))
        let width = min((text as NSString).size(withAttributes: [.font: font]).width, 900)
        return CGRect(x: caret.maxX - width, y: caret.minY, width: width, height: caret.height)
    }

    /// A small rectangle under the pointer, for when the cursor can't be found.
    @MainActor
    static func pointerRect() -> CGRect {
        let location = NSEvent.mouseLocation
        return CGRect(x: location.x, y: location.y - 18, width: 1, height: 18)
    }

    // MARK: Accessibility

    private static func focusedElement(_ snapshot: ScreenSnapshot) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            logOnce(snapshot, "no focused element (AXError \(error.rawValue))")
            askElectronAppForAccessibility(snapshot)
            return nil
        }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func selectionLocation(_ element: AXUIElement, _ snapshot: ScreenSnapshot) -> Int? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            logOnce(snapshot, "no text range (AXError \(error.rawValue))")
            askElectronAppForAccessibility(snapshot)
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    private static func rangeCaret(_ element: AXUIElement, at location: Int, _ snapshot: ScreenSnapshot) -> CGRect? {
        // The empty range at the cursor works in many apps; otherwise use the character before it.
        if let rect = bounds(element, range: CFRange(location: location, length: 0)), rect.height > 1 {
            return toAppKit(rect, snapshot)
        }
        if location > 0, let rect = bounds(element, range: CFRange(location: location - 1, length: 1)), rect.height > 1 {
            return toAppKit(CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height), snapshot)
        }
        logOnce(snapshot, "no bounds for character ranges")
        return nil
    }

    private static func markerCaret(_ element: AXUIElement, _ snapshot: ScreenSnapshot) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markerRange else {
            logOnce(snapshot, "no text markers")
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForTextMarkerRange" as CFString, markerRange, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            logOnce(snapshot, "text markers without bounds")
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 1, rect.origin != .zero else { return nil }
        // A collapsed range has no width; the cursor sits at its right edge.
        return toAppKit(CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height), snapshot)
    }

    private static func fieldRect(_ element: AXUIElement, _ snapshot: ScreenSnapshot) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            logOnce(snapshot, "no text field frame")
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        logOnce(snapshot, "using the text field frame")
        // A line-high strip along the field's bottom edge (or its whole height if it's one line).
        let lineHeight = min(size.height, 22)
        return toAppKit(CGRect(x: position.x + 6, y: position.y + size.height - lineHeight, width: 1, height: lineHeight), snapshot)
    }

    private static func bounds(_ element: AXUIElement, range: CFRange) -> CGRect? {
        var range = range
        guard let argument = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, argument, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.origin != .zero else { return nil }
        return rect
    }

    /// Electron apps (Slack, Discord, VS Code…) only expose text positions once asked to.
    /// Harmless for other apps, and asked once per process.
    private static func askElectronAppForAccessibility(_ snapshot: ScreenSnapshot) {
        guard let pid = snapshot.pid, pid != ProcessInfo.processInfo.processIdentifier,
              seen.withLock({ $0.insert("ask:\(pid)").inserted }) else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func logOnce(_ snapshot: ScreenSnapshot, _ reason: String) {
        let key = "\(snapshot.bundleID):\(reason)"
        guard seen.withLock({ $0.insert(key).inserted }) else { return }
        quillLog.notice("Caret: \(snapshot.bundleID, privacy: .public): \(reason, privacy: .public)")
    }

    /// Accessibility uses a top-left origin on the primary display; AppKit uses bottom-left.
    private static func toAppKit(_ rect: CGRect, _ snapshot: ScreenSnapshot) -> CGRect? {
        let converted = CGRect(x: rect.minX, y: snapshot.primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
        let onScreen = snapshot.screens.contains { $0.insetBy(dx: -2, dy: -2).intersects(converted) }
        return onScreen ? converted : nil
    }
}
