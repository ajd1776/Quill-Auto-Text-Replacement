// Renders Quill's app icon at every macOS size: swift Tools/make-icon.swift <appiconset dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas: CGFloat = 1024

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)

    // macOS icon grid: 824pt body centred on a 1024 canvas, continuous-corner radius ~185.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); shape.fill()
    ctx.restoreGState()

    // Ink gradient
    ctx.saveGState()
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.47, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.16, blue: 0.62, alpha: 1),
        NSColor(srgbRed: 0.09, green: 0.07, blue: 0.30, alpha: 1),
    ])!
    gradient.draw(in: body, angle: -65)

    // Top sheen
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: -90)

    // Glyph
    let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let rect = CGRect(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2 - 6,
                          width: size.width, height: size.height)
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        symbol.draw(in: rect)
    }
    ctx.restoreGState()

    // Hairline edge highlight
    NSColor.white.withAlphaComponent(0.22).setStroke()
    shape.lineWidth = 4
    shape.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(px).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons")
