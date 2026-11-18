import AppKit
import SwiftUI

/// Lets SwiftUI insert text at the editor's cursor.
@MainActor
final class TokenEditorController {
    fileprivate weak var textView: NSTextView?

    /// Inserts text at the cursor. With `selecting`, selects that part of the inserted text so it can be typed over.
    func insert(_ string: String, selecting part: String? = nil) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let start = textView.selectedRange().location
        textView.insertText(string, replacementRange: textView.selectedRange())
        if let part, let range = string.range(of: part) {
            let offset = string.utf16.distance(from: string.startIndex, to: range.lowerBound)
            textView.setSelectedRange(NSRange(location: start + offset, length: part.utf16.count))
        }
    }
}

/// A plain-text editor that shows tokens such as {date} and {input:Name} as rounded chips.
struct TokenTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: TokenEditorController
    var fontSize: CGFloat = 15
    var inset = NSSize(width: 23, height: 14)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 with a custom layout manager, so token backgrounds can be drawn rounded.
        let storage = NSTextStorage()
        let layout = ChipLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = inset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel("Expands to")
        textView.string = text
        context.coordinator.highlight(textView)
        controller.textView = textView

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            context.coordinator.highlight(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TokenTextEditor

        init(_ parent: TokenTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            highlight(textView)
            parent.text = textView.string
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let text = storage.string
            let whole = NSRange(location: 0, length: (text as NSString).length)
            let base: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: parent.fontSize),
                .foregroundColor: NSColor.textColor,
            ]
            storage.beginEditing()
            storage.setAttributes(base, range: whole)
            for match in TokenRenderer.tokenPattern.matches(in: text, range: whole) {
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: parent.fontSize - 1, weight: .medium),
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.16),
                ], range: match.range)
            }
            storage.endEditing()
            textView.typingAttributes = base
        }
    }
}

/// Draws background colour (used only for tokens) as rounded chips.
private final class ChipLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        color.setFill()
        for index in 0..<rectCount {
            let rect = rectArray[index].insetBy(dx: -2, dy: 1)
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
    }
}
