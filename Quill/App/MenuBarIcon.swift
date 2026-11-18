import AppKit

/// The choice of menu bar icon. Custom nib icons are template assets; the rest are SF Symbols.
/// When Quill is off or paused, a slash is drawn across whichever icon is chosen.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case enchantedNib, nib, solidNib, writingNib, quillFeather
    case pencilLine, penAndScribble, signature, typingCursor, magicWand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enchantedNib: "Enchanted Nib"
        case .nib: "Nib"
        case .solidNib: "Solid Nib"
        case .writingNib: "Writing Nib"
        case .quillFeather: "Quill Feather"
        case .pencilLine: "Pencil Line"
        case .penAndScribble: "Pen and Scribble"
        case .signature: "Signature"
        case .typingCursor: "Typing Cursor"
        case .magicWand: "Magic Wand"
        }
    }

    private var assetName: String? {
        switch self {
        case .enchantedNib: "MenuBar-nib-sparkle"
        case .nib: "MenuBar-nib-outline"
        case .solidNib: "MenuBar-nib-filled"
        case .writingNib: "MenuBar-nib-tilted"
        case .quillFeather: "MenuBar-quill-feather"
        default: nil
        }
    }

    private var symbolName: String {
        switch self {
        case .pencilLine: "pencil.line"
        case .penAndScribble: "pencil.and.scribble"
        case .signature: "signature"
        case .typingCursor: "character.cursor.ibeam"
        case .magicWand: "wand.and.stars"
        default: "pencil.line"
        }
    }

    private var baseImage: NSImage {
        if let assetName, let image = NSImage(named: assetName) { return image }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
    }

    /// An 18 pt template image; with `isOn` false, the icon is crossed through.
    func image(isOn: Bool) -> NSImage {
        let base = baseImage
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            // Fit the icon inside the square without stretching symbols that aren't square.
            let size = base.size.width > 0 ? base.size : rect.size
            let scale = min(rect.width / size.width, rect.height / size.height, 1.2)
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            base.draw(in: CGRect(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2,
                                 width: drawn.width, height: drawn.height))
            guard !isOn, let context = NSGraphicsContext.current?.cgContext else { return true }
            let slash = NSBezierPath()
            slash.move(to: CGPoint(x: 2, y: side - 1.5))
            slash.line(to: CGPoint(x: side - 2, y: 1.5))
            slash.lineCapStyle = .round
            context.setBlendMode(.clear)
            slash.lineWidth = 3.6
            slash.stroke()
            context.setBlendMode(.normal)
            NSColor.black.setStroke()
            slash.lineWidth = 1.4
            slash.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
