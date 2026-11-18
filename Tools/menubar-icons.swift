// Renders menu bar icon candidates and a preview sheet:
//   swift Tools/menubar-icons.swift <output folder>
// Custom icons are drawn as black-on-clear templates (macOS tints them for light and dark menu bars).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let unit: CGFloat = 36   // template canvas (18 pt @2x)

/// A fountain-pen nib pointing down, in a 0…1 box.
func nib(in rect: CGRect, filled: Bool) -> NSBezierPath {
    let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
    let p = NSBezierPath()
    p.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02))
    p.curve(to: CGPoint(x: x + w * 0.16, y: y + h * 0.56), controlPoint1: CGPoint(x: x + w * 0.38, y: y + h * 0.18), controlPoint2: CGPoint(x: x + w * 0.16, y: y + h * 0.36))
    p.line(to: CGPoint(x: x + w * 0.24, y: y + h * 0.78))
    p.line(to: CGPoint(x: x + w * 0.76, y: y + h * 0.78))
    p.line(to: CGPoint(x: x + w * 0.84, y: y + h * 0.56))
    p.curve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02), controlPoint1: CGPoint(x: x + w * 0.84, y: y + h * 0.36), controlPoint2: CGPoint(x: x + w * 0.62, y: y + h * 0.18))
    p.close()
    p.appendRoundedRect(CGRect(x: x + w * 0.2, y: y + h * 0.82, width: w * 0.6, height: h * 0.16), xRadius: w * 0.05, yRadius: w * 0.05)
    p.lineWidth = w * 0.09
    p.lineJoinStyle = .round
    return p
}

func sparkle(at c: CGPoint, size s: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: c.x, y: c.y + s))
    p.curve(to: CGPoint(x: c.x + s, y: c.y), controlPoint1: CGPoint(x: c.x + s * 0.15, y: c.y + s * 0.15), controlPoint2: CGPoint(x: c.x + s * 0.15, y: c.y + s * 0.15))
    p.curve(to: CGPoint(x: c.x, y: c.y - s), controlPoint1: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.15), controlPoint2: CGPoint(x: c.x + s * 0.15, y: c.y - s * 0.15))
    p.curve(to: CGPoint(x: c.x - s, y: c.y), controlPoint1: CGPoint(x: c.x - s * 0.15, y: c.y - s * 0.15), controlPoint2: CGPoint(x: c.x - s * 0.15, y: c.y - s * 0.15))
    p.curve(to: CGPoint(x: c.x, y: c.y + s), controlPoint1: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.15), controlPoint2: CGPoint(x: c.x - s * 0.15, y: c.y + s * 0.15))
    return p
}

/// Each candidate draws into a unit×unit box in black.
let custom: [(id: String, title: String, draw: (CGContext) -> Void)] = [
    ("nib-outline", "Nib", { ctx in
        let p = nib(in: CGRect(x: 7, y: 2, width: 22, height: 32), filled: false)
        NSColor.black.setStroke(); p.stroke()
        NSColor.black.setFill(); NSBezierPath(ovalIn: CGRect(x: 15.5, y: 15, width: 5, height: 5)).fill()
        let slit = NSBezierPath(); slit.move(to: CGPoint(x: 18, y: 15)); slit.line(to: CGPoint(x: 18, y: 4)); slit.lineWidth = 2; slit.stroke()
    }),
    ("nib-off", "Nib (Off)", { ctx in
        let p = nib(in: CGRect(x: 7, y: 2, width: 22, height: 32), filled: false)
        NSColor.black.setStroke(); p.stroke()
        NSColor.black.setFill(); NSBezierPath(ovalIn: CGRect(x: 15.5, y: 15, width: 5, height: 5)).fill()
        // Diagonal slash, with a clear gap either side so it reads at 18 pt.
        let slash = NSBezierPath(); slash.move(to: CGPoint(x: 4, y: 33)); slash.line(to: CGPoint(x: 32, y: 3))
        ctx.setBlendMode(.clear); slash.lineWidth = 7; slash.stroke()
        ctx.setBlendMode(.normal); slash.lineWidth = 2.6; slash.lineCapStyle = .round; slash.stroke()
    }),
    ("nib-filled", "Solid Nib", { ctx in
        let p = nib(in: CGRect(x: 7, y: 2, width: 22, height: 32), filled: true)
        NSColor.black.setFill(); p.fill()
        ctx.setBlendMode(.clear)
        NSBezierPath(ovalIn: CGRect(x: 15.5, y: 15, width: 5, height: 5)).fill()
        let slit = NSBezierPath(); slit.move(to: CGPoint(x: 18, y: 16)); slit.line(to: CGPoint(x: 18, y: 2)); slit.lineWidth = 2.2; slit.stroke()
    }),
    ("nib-sparkle", "Enchanted Nib", { ctx in
        let p = nib(in: CGRect(x: 4, y: 2, width: 20, height: 29), filled: false)
        NSColor.black.setStroke(); p.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: CGRect(x: 11.8, y: 13.5, width: 4.4, height: 4.4)).fill()
        sparkle(at: CGPoint(x: 29, y: 27), size: 6).fill()
        sparkle(at: CGPoint(x: 31, y: 13), size: 3.4).fill()
    }),
    ("nib-tilted", "Writing Nib", { ctx in
        ctx.translateBy(x: 18, y: 18); ctx.rotate(by: 40 * .pi / 180); ctx.translateBy(x: -18, y: -18)
        let p = nib(in: CGRect(x: 8, y: 6, width: 20, height: 28), filled: true)
        NSColor.black.setFill(); p.fill()
        ctx.setBlendMode(.clear)
        NSBezierPath(ovalIn: CGRect(x: 16, y: 17, width: 4.4, height: 4.4)).fill()
        let slit = NSBezierPath(); slit.move(to: CGPoint(x: 18, y: 18)); slit.line(to: CGPoint(x: 18, y: 6)); slit.lineWidth = 2; slit.stroke()
        ctx.setBlendMode(.normal)
        ctx.translateBy(x: 18, y: 18); ctx.rotate(by: -40 * .pi / 180); ctx.translateBy(x: -18, y: -18)
        let ink = NSBezierPath(); ink.move(to: CGPoint(x: 2, y: 5)); ink.curve(to: CGPoint(x: 15, y: 5), controlPoint1: CGPoint(x: 6, y: 1), controlPoint2: CGPoint(x: 11, y: 9))
        ink.lineWidth = 2.6; ink.lineCapStyle = .round; NSColor.black.setStroke(); ink.stroke()
    }),
    ("quill-feather", "Quill Feather", { ctx in
        let p = NSBezierPath()
        p.move(to: CGPoint(x: 6, y: 3))
        p.curve(to: CGPoint(x: 31, y: 33), controlPoint1: CGPoint(x: 8, y: 18), controlPoint2: CGPoint(x: 20, y: 32))
        p.curve(to: CGPoint(x: 9, y: 9), controlPoint1: CGPoint(x: 30, y: 21), controlPoint2: CGPoint(x: 22, y: 10))
        p.close()
        NSColor.black.setFill(); p.fill()
        ctx.setBlendMode(.clear)
        let spine = NSBezierPath(); spine.move(to: CGPoint(x: 7, y: 4)); spine.curve(to: CGPoint(x: 28, y: 30), controlPoint1: CGPoint(x: 14, y: 14), controlPoint2: CGPoint(x: 21, y: 23))
        spine.lineWidth = 1.8; spine.lineCapStyle = .round; spine.stroke()
        for (a, b) in [(CGPoint(x: 13, y: 13), CGPoint(x: 19, y: 12)), (CGPoint(x: 18, y: 19), CGPoint(x: 25, y: 19))] {
            let cut = NSBezierPath(); cut.move(to: a); cut.line(to: b); cut.lineWidth = 1.6; cut.stroke()
        }
    }),
]

let symbols: [(id: String, title: String)] = [
    ("pencil.line", "Pencil Line (current)"),
    ("pencil.and.scribble", "Pen and Scribble"),
    ("signature", "Signature"),
    ("character.cursor.ibeam", "Typing Cursor"),
    ("wand.and.stars", "Magic Wand"),
]

func template(_ draw: @escaping (CGContext) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: unit, height: unit), flipped: false) { _ in
        draw(NSGraphicsContext.current!.cgContext); return true
    }
    image.isTemplate = true
    return image
}

func writePNG(_ image: NSImage, size: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// Template PNGs for the custom icons (18 pt and @2x), ready for an asset catalog.
for item in custom {
    let image = template(item.draw)
    writePNG(image, size: 18, to: out.appendingPathComponent("\(item.id).png"))
    writePNG(image, size: 36, to: out.appendingPathComponent("\(item.id)@2x.png"))
}

// Preview sheet: each icon in a light and a dark menu bar.
var all: [(title: String, image: NSImage)] = custom.map { ($0.title, template($0.draw)) }
for symbol in symbols {
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    all.append((symbol.title, NSImage(systemSymbolName: symbol.id, accessibilityDescription: nil)!.withSymbolConfiguration(config)!))
}

let scale: CGFloat = 2, cellW: CGFloat = 220, rowH: CGFloat = 46, pad: CGFloat = 16
let width = pad * 2 + cellW * 2, height = pad * 2 + 30 + rowH * CGFloat(all.count)
let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
sheet.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(white: 0.12, alpha: 1).setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
("Light menu bar" as NSString).draw(at: CGPoint(x: pad + 8, y: height - pad - 18), withAttributes: titleAttrs)
("Dark menu bar" as NSString).draw(at: CGPoint(x: pad + cellW + 8, y: height - pad - 18), withAttributes: titleAttrs)
for (index, item) in all.enumerated() {
    let y = height - pad - 30 - rowH * CGFloat(index + 1)
    for (column, dark) in [(0, false), (1, true)] {
        let bar = CGRect(x: pad + cellW * CGFloat(column) + 4, y: y + 6, width: cellW - 8, height: 34)
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7).fill()
        let tint = dark ? NSColor.white : NSColor.black
        let tinted = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            item.image.draw(in: rect)
            tint.set(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: CGRect(x: bar.minX + 12, y: bar.midY - 9, width: 18, height: 18))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: dark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.2, alpha: 1)]
        ("\(index + 1). \(item.title)" as NSString).draw(at: CGPoint(x: bar.minX + 40, y: bar.midY - 8), withAttributes: attrs)
    }
}
NSGraphicsContext.restoreGraphicsState()
try! sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("menubar-icons-preview.png"))
print("rendered \(all.count) menu bar icons")
