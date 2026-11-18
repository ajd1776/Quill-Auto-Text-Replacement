import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class FillInModel {
    let snippet: Snippet
    let fields: [String]
    let group: SnippetGroup?
    var values: [String: String]

    init(snippet: Snippet, fields: [String], group: SnippetGroup?) {
        self.snippet = snippet
        self.fields = fields
        self.group = group
        self.values = Dictionary(uniqueKeysWithValues: fields.map { ($0, "") })
    }

    var preview: String {
        let filled = values.mapValues { $0.isEmpty ? "…" : $0 }
        return TokenRenderer.render(snippet.expansion, inputs: filled, clipboard: NSPasteboard.general.string(forType: .string)).text
    }
}

/// The small form that asks for {input:Label} values before a snippet expands.
/// A non-activating panel, so the app you're typing in stays frontmost and gets the result.
@MainActor
final class FillInController: NSObject, NSWindowDelegate {
    static let shared = FillInController()

    private var panel: FloatingPanel?
    private var completion: (([String: String]?) -> Void)?
    #if DEBUG
    /// Screenshot demos show the form without taking keyboard focus.
    static var demoWithoutFocus = false
    #endif
    private let width: CGFloat = 400

    func present(snippet: Snippet, fields: [String], completion: @escaping ([String: String]?) -> Void) {
        finish(with: nil)
        self.completion = completion

        let model = FillInModel(snippet: snippet, fields: fields, group: AppState.shared.store.group(for: snippet))
        let view = FillInView(
            model: model,
            onInsert: { [weak self] in self?.finish(with: model.values) },
            onCancel: { [weak self] in self?.finish(with: nil) }
        )
        // Measure the form properly; a bare NSHostingView with no sizing options reports zero.
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        let measured = controller.sizeThatFits(in: CGSize(width: width, height: 2000))
        let size = CGSize(width: width, height: max(measured.height, 200))

        CaretLocator.lookup({ CaretLocator.caret($0, fieldFallback: true) }) { [weak self] caret in
            guard let self, self.completion != nil else { return }
            let panel = FloatingPanel(contentRect: self.frame(for: size, near: caret))
            panel.contentViewController = controller
            panel.setContentSize(size)
            panel.delegate = self
            self.panel = panel
            #if DEBUG
            if Self.demoWithoutFocus {
                panel.orderFrontRegardless()
                return
            }
            #endif
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(with: nil)
    }

    /// Below the cursor when there's room, otherwise near the top of the screen.
    private func frame(for size: CGSize, near caret: CGRect?) -> CGRect {
        let anchor = caret ?? CaretLocator.pointerRect()
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var y = anchor.minY - size.height - 8
        if y < screen.minY { y = anchor.maxY + 8 }
        y = min(max(y, screen.minY), screen.maxY - size.height)
        let x = min(max(anchor.minX - 20, screen.minX + 8), screen.maxX - size.width - 8)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func finish(with values: [String: String]?) {
        guard let completion else { return }
        self.completion = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        // Let focus return to the app you were typing in before typing the result.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            completion(values)
        }
    }
}

struct FillInView: View {
    let model: FillInModel
    let onInsert: () -> Void
    let onCancel: () -> Void

    @FocusState private var focused: String?

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SnippetIcon(symbol: model.snippet.symbol ?? model.group?.symbol, color: model.group?.color.color ?? .accentColor, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.snippet.trigger)
                        .font(.headline.monospaced())
                    Text(model.fields.count == 1 ? "Fill in 1 field" : "Fill in \(model.fields.count) fields")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(model.fields, id: \.self) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField(field, text: Binding(
                        get: { model.values[field] ?? "" },
                        set: { model.values[field] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused, equals: field)
                    .onSubmit { advance(from: field) }
                }
            }

            Text(model.preview)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Preview: \(model.preview)")

            HStack {
                Text("⇥ next field · ↩ insert · esc cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Insert", action: onInsert)
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle()
            }
        }
        .padding(20)
        .frame(width: 400)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            DispatchQueue.main.async { focused = model.fields.first }
        }
    }

    /// Return moves to the next field, and inserts from the last one.
    private func advance(from field: String) {
        guard let index = model.fields.firstIndex(of: field), index + 1 < model.fields.count else {
            onInsert()
            return
        }
        focused = model.fields[index + 1]
    }
}
