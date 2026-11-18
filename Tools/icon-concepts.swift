// Renders app icon concepts: swift Tools/icon-concepts.swift <output folder>
// Each concept: a pen glyph with depth and an "enchanted" glint sweeping across it.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A symbol rendered as a white mask image the size of the canvas.
func symbolMask(_ name: String, pointSize: CGFloat, offset: CGPoint = .zero, rotation: CGFloat = 0) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold).applying(.init(paletteColors: [.white]))
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    ctx.translateBy(x: canvas / 2 + offset.x, y: canvas / 2 + offset.y)
    ctx.rotate(by: rotation * .pi / 180)
    image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

/// A fountain-pen nib drawn by hand (tip pointing down-left), as a mask, plus its slit and breather hole.
func nibPath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: 0, y: -330))                       // tip
    p.curve(to: CGPoint(x: -190, y: 40), controlPoint1: CGPoint(x: -60, y: -230), controlPoint2: CGPoint(x: -190, y: -120))
    p.line(to: CGPoint(x: -150, y: 200))                      // left shoulder
    p.curve(to: CGPoint(x: 150, y: 200), controlPoint1: CGPoint(x: -80, y: 260), controlPoint2: CGPoint(x: 80, y: 260))
    p.line(to: CGPoint(x: 190, y: 40))                        // right shoulder
    p.curve(to: CGPoint(x: 0, y: -330), controlPoint1: CGPoint(x: 190, y: -120), controlPoint2: CGPoint(x: 60, y: -230))
    p.close()
    // Barrel collar above the nib.
    p.appendRoundedRect(CGRect(x: -175, y: 225, width: 350, height: 110), xRadius: 30, yRadius: 30)
    return p
}

func nibMask(rotation: CGFloat, offset: CGPoint) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: canvas / 2 + offset.x, y: canvas / 2 + offset.y)
    ctx.rotate(by: rotation * .pi / 180)
    NSColor.white.setFill()
    nibPath().fill()
    // Cut the slit and breather hole out.
    ctx.setBlendMode(.clear)
    NSBezierPath(ovalIn: CGRect(x: -30, y: -30, width: 60, height: 60)).fill()
    let slit = NSBezierPath()
    slit.move(to: CGPoint(x: 0, y: -20)); slit.line(to: CGPoint(x: 0, y: -315))
    slit.lineWidth = 14; slit.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

/// Diagonal glint bands, like light sliding across an enchanted item.
func drawGlint(_ ctx: CGContext, phase: CGFloat, colors: [NSColor]) {
    ctx.saveGState()
    ctx.translateBy(x: canvas / 2, y: canvas / 2)
    ctx.rotate(by: -32 * .pi / 180)
    let bands: [(x: CGFloat, w: CGFloat, a: CGFloat)] = [(-260 + phase, 150, 0.85), (-40 + phase, 60, 0.55), (180 + phase, 220, 0.7)]
    for band in bands {
        let rect = CGRect(x: band.x, y: -900, width: band.w, height: 1800)
        let gradient = NSGradient(colors: [colors[0].withAlphaComponent(0), colors[0].withAlphaComponent(band.a),
                                           colors[1].withAlphaComponent(band.a), colors[1].withAlphaComponent(0)])!
        gradient.draw(in: rect, angle: 0)
    }
    ctx.restoreGState()
}

func render(_ name: String, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
}

/// Squircle base with drop shadow, gradient, top sheen and inner rim: the "depth" layers.
func base(_ ctx: CGContext, top: NSColor, mid: NSColor, bottom: NSColor, rim: NSColor) {
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    bottom.setFill(); shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [top, mid, bottom])!.draw(in: body, angle: -90)
    // Soft radial glow behind the glyph.
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    glow.draw(fromCenter: CGPoint(x: 512, y: 560), radius: 0, toCenter: CGPoint(x: 512, y: 560), radius: 430, options: [])
    // Top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
    ctx.restoreGState()

    // Bevel: light rim on top, dark rim at the bottom.
    let inner = NSBezierPath(roundedRect: body.insetBy(dx: 4, dy: 4), xRadius: radius - 4, yRadius: radius - 4)
    inner.lineWidth = 8
    ctx.saveGState()
    shape.addClip()
    NSGradient(colors: [rim.withAlphaComponent(0), rim.withAlphaComponent(0.28)])!.draw(in: CGRect(x: 100, y: 512, width: 824, height: 412), angle: 90)
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    inner.stroke()
}

/// A glyph in white with depth (shadow + bottom shade) and an enchanted glint clipped to its shape.
func glyph(_ ctx: CGContext, mask: CGImage, glintColors: [NSColor], shade: NSColor) {
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    // Drop shadow under the glyph.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.clip(to: full, mask: mask)
    NSColor.white.setFill(); ctx.fill(full)
    ctx.restoreGState()
    // Body: white to lavender, so the glyph reads as rounded.
    ctx.saveGState()
    ctx.clip(to: full, mask: mask)
    NSGradient(colors: [NSColor.white, color(0xEDE4FF), shade])!.draw(in: full, angle: -90)
    // The enchantment glint, only on the glyph.
    ctx.setBlendMode(.plusLighter)
    drawGlint(ctx, phase: 0, colors: glintColors)
    ctx.restoreGState()
}

/// Little four-point sparkles.
func sparkles(_ ctx: CGContext, _ points: [(CGFloat, CGFloat, CGFloat)], tint: NSColor) {
    for (x, y, size) in points {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: y + size))
        path.curve(to: CGPoint(x: x + size, y: y), controlPoint1: CGPoint(x: x + size * 0.12, y: y + size * 0.12), controlPoint2: CGPoint(x: x + size * 0.12, y: y + size * 0.12))
        path.curve(to: CGPoint(x: x, y: y - size), controlPoint1: CGPoint(x: x + size * 0.12, y: y - size * 0.12), controlPoint2: CGPoint(x: x + size * 0.12, y: y - size * 0.12))
        path.curve(to: CGPoint(x: x - size, y: y), controlPoint1: CGPoint(x: x - size * 0.12, y: y - size * 0.12), controlPoint2: CGPoint(x: x - size * 0.12, y: y - size * 0.12))
        path.curve(to: CGPoint(x: x, y: y + size), controlPoint1: CGPoint(x: x - size * 0.12, y: y + size * 0.12), controlPoint2: CGPoint(x: x - size * 0.12, y: y + size * 0.12))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: size * 0.8, color: tint.cgColor)
        NSColor.white.setFill(); path.fill()
        ctx.restoreGState()
    }
}

// 1. Enchanted Quill: deep violet, the pen-and-scribble glyph with a strong glint.
render("concept-1-enchanted-quill") { ctx in
    base(ctx, top: color(0x8B5CF6), mid: color(0x5B21B6), bottom: color(0x2E1065), rim: color(0xC4B5FD))
    glyph(ctx, mask: symbolMask("pencil.and.scribble", pointSize: 430, offset: CGPoint(x: 0, y: -10)),
          glintColors: [color(0xE879F9), color(0xA78BFA)], shade: color(0xC4B5FD))
    sparkles(ctx, [(745, 760, 30), (300, 735, 18), (760, 330, 16)], tint: color(0xE879F9))
}

// 2. Glinted Nib: a large fountain-pen nib, glowing ink dot, cosmic violet.
render("concept-2-glinted-nib") { ctx in
    base(ctx, top: color(0x7C3AED), mid: color(0x4C1D95), bottom: color(0x1E0A3C), rim: color(0xDDD6FE))
    // Ink glow under the nib.
    // Glowing ink where the tip touches down.
    let ink = NSGradient(colors: [color(0xF0ABFC, 0.95), color(0xA855F7, 0.0)])!
    ink.draw(fromCenter: CGPoint(x: 704, y: 269), radius: 0, toCenter: CGPoint(x: 704, y: 269), radius: 170, options: [])
    glyph(ctx, mask: nibMask(rotation: 40, offset: CGPoint(x: -20, y: 10)),
          glintColors: [color(0xF0ABFC), color(0x818CF8)], shade: color(0xA78BFA))
    sparkles(ctx, [(712, 262, 36), (300, 360, 18), (770, 700, 22), (420, 800, 12)], tint: color(0xF0ABFC))
}

// 3. Light Script: a white-and-lavender tile with a violet pen writing a glowing line.
render("concept-3-light-script") { ctx in
    base(ctx, top: color(0xFFFFFF), mid: color(0xF3EEFF), bottom: color(0xDCCFFF), rim: color(0xFFFFFF))
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    // Violet glyph with glint (inverted palette for the light tile).
    let mask = symbolMask("signature", pointSize: 470, offset: CGPoint(x: -10, y: -20))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x4C1D95, 0.45).cgColor)
    ctx.clip(to: full, mask: mask)
    color(0x6D28D9).setFill(); ctx.fill(full)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.clip(to: full, mask: mask)
    NSGradient(colors: [color(0xA78BFA), color(0x7C3AED), color(0x4C1D95)])!.draw(in: full, angle: -90)
    ctx.setBlendMode(.plusLighter)
    drawGlint(ctx, phase: 30, colors: [color(0xF5D0FE), color(0xC7D2FE)])
    ctx.restoreGState()
    sparkles(ctx, [(760, 740, 30), (290, 360, 18)], tint: color(0xA855F7))
}
print("rendered 3 concepts")

// MARK: - Nib variations

func nibMaskScaled(rotation: CGFloat, offset: CGPoint, scale: CGFloat) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: canvas / 2 + offset.x, y: canvas / 2 + offset.y)
    ctx.rotate(by: rotation * .pi / 180)
    ctx.scaleBy(x: scale, y: scale)
    NSColor.white.setFill()
    nibPath().fill()
    ctx.setBlendMode(.clear)
    NSBezierPath(ovalIn: CGRect(x: -30, y: -30, width: 60, height: 60)).fill()
    let slit = NSBezierPath()
    slit.move(to: CGPoint(x: 0, y: -20)); slit.line(to: CGPoint(x: 0, y: -315))
    slit.lineWidth = 14; slit.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

/// The nib in white with a 3D centre ridge, engraving, depth and glint.
func nib(_ ctx: CGContext, rotation: CGFloat, offset: CGPoint, scale: CGFloat, glint: [NSColor], glintStrength: CGFloat = 1) {
    let full = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let mask = nibMaskScaled(rotation: rotation, offset: offset, scale: scale)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 6, height: -20), blur: 34, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    ctx.clip(to: full, mask: mask)
    NSColor.white.setFill(); ctx.fill(full)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.clip(to: full, mask: mask)
    NSGradient(colors: [NSColor.white, color(0xF1EAFF), color(0xC9B6FF)])!.draw(in: full, angle: -90)
    // Centre ridge: shade the far half of the nib so it reads as folded metal.
    ctx.saveGState()
    ctx.translateBy(x: canvas / 2 + offset.x, y: canvas / 2 + offset.y)
    ctx.rotate(by: rotation * .pi / 180)
    ctx.scaleBy(x: scale, y: scale)
    NSGradient(colors: [color(0x7C3AED, 0.0), color(0x5B21B6, 0.32)])!.draw(in: CGRect(x: 0, y: -340, width: 200, height: 690), angle: 0)
    // Engraved scroll on the nib face.
    let engraving = NSBezierPath()
    engraving.move(to: CGPoint(x: -110, y: 110))
    engraving.curve(to: CGPoint(x: 110, y: 110), controlPoint1: CGPoint(x: -60, y: 165), controlPoint2: CGPoint(x: 60, y: 165))
    engraving.move(to: CGPoint(x: -80, y: 70))
    engraving.curve(to: CGPoint(x: 80, y: 70), controlPoint1: CGPoint(x: -40, y: 110), controlPoint2: CGPoint(x: 40, y: 110))
    engraving.lineWidth = 7
    engraving.lineCapStyle = .round
    color(0x6D28D9, 0.35).setStroke(); engraving.stroke()
    // Collar band line.
    color(0x6D28D9, 0.25).setFill()
    NSBezierPath(rect: CGRect(x: -175, y: 268, width: 350, height: 10)).fill()
    ctx.restoreGState()
    // Glint.
    ctx.setBlendMode(.plusLighter)
    ctx.setAlpha(glintStrength)
    drawGlint(ctx, phase: 0, colors: glint)
    ctx.restoreGState()
}

/// Where the nib's tip lands for a given rotation, offset and scale.
func tipPoint(rotation: CGFloat, offset: CGPoint, scale: CGFloat) -> CGPoint {
    let r = rotation * .pi / 180
    let x: CGFloat = 0, y: CGFloat = -330 * scale
    return CGPoint(x: canvas / 2 + offset.x + x * cos(r) - y * sin(r), y: canvas / 2 + offset.y + x * sin(r) + y * cos(r))
}

func inkGlow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat) {
    NSGradient(colors: [color(0xFBCFE8, 0.95), color(0xC084FC, 0.55), color(0xA855F7, 0.0)])!
        .draw(fromCenter: p, radius: 0, toCenter: p, radius: radius, options: [])
}

/// A glowing ink stroke.
func inkStroke(_ ctx: CGContext, _ path: NSBezierPath, width: CGFloat) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: color(0xE879F9, 0.95).cgColor)
    path.lineWidth = width
    color(0xF5D0FE).setStroke(); path.stroke()
    ctx.restoreGState()
    path.lineWidth = width * 0.45
    NSColor.white.setStroke(); path.stroke()
}

// A. Ink Flourish
render("nib-a-ink-flourish") { ctx in
    base(ctx, top: color(0x8B5CF6), mid: color(0x5B21B6), bottom: color(0x241046), rim: color(0xDDD6FE))
    let rot: CGFloat = 40, off = CGPoint(x: 40, y: 10), sc: CGFloat = 0.82
    let tip = tipPoint(rotation: rot, offset: off, scale: sc)
    let flourish = NSBezierPath()
    flourish.move(to: CGPoint(x: 210, y: 300))
    flourish.curve(to: CGPoint(x: 430, y: 250), controlPoint1: CGPoint(x: 260, y: 200), controlPoint2: CGPoint(x: 360, y: 330))
    flourish.curve(to: tip, controlPoint1: CGPoint(x: 500, y: 170), controlPoint2: CGPoint(x: tip.x - 70, y: tip.y - 60))
    inkStroke(ctx, flourish, width: 26)
    inkGlow(ctx, at: tip, radius: 140)
    nib(ctx, rotation: rot, offset: off, scale: sc, glint: [color(0xF0ABFC), color(0x818CF8)])
    sparkles(ctx, [(tip.x + 8, tip.y - 6, 34), (300, 720, 18), (790, 760, 24), (230, 440, 12)], tint: color(0xF0ABFC))
}

// B. Enchanting Circle
render("nib-b-enchanting-circle") { ctx in
    base(ctx, top: color(0x7C3AED), mid: color(0x4C1D95), bottom: color(0x1A0B33), rim: color(0xDDD6FE))
    let center = CGPoint(x: 512, y: 500)
    // Glowing rune ring.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color(0xE879F9, 0.9).cgColor)
    let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 310, y: center.y - 310, width: 620, height: 620))
    ring.lineWidth = 6
    color(0xF5D0FE, 0.9).setStroke(); ring.stroke()
    let inner = NSBezierPath(ovalIn: CGRect(x: center.x - 265, y: center.y - 265, width: 530, height: 530))
    inner.lineWidth = 3
    let dash: [CGFloat] = [18, 22]
    inner.setLineDash(dash, count: 2, phase: 0)
    color(0xE9D5FF, 0.75).setStroke(); inner.stroke()
    // Rune ticks around the ring.
    for i in 0..<16 {
        let a = CGFloat(i) / 16 * 2 * .pi
        let p1 = CGPoint(x: center.x + cos(a) * 280, y: center.y + sin(a) * 280)
        let p2 = CGPoint(x: center.x + cos(a) * (i.isMultiple(of: 2) ? 300 : 292), y: center.y + sin(a) * (i.isMultiple(of: 2) ? 300 : 292))
        let tick = NSBezierPath(); tick.move(to: p1); tick.line(to: p2); tick.lineWidth = 6; tick.lineCapStyle = .round
        color(0xF5D0FE).setStroke(); tick.stroke()
    }
    ctx.restoreGState()
    NSGradient(colors: [color(0xC084FC, 0.35), color(0xC084FC, 0)])!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: 300, options: [])
    let rot: CGFloat = 40, off = CGPoint(x: 0, y: 0), sc: CGFloat = 0.8
    let tip = tipPoint(rotation: rot, offset: off, scale: sc)
    inkGlow(ctx, at: tip, radius: 110)
    nib(ctx, rotation: rot, offset: off, scale: sc, glint: [color(0xF0ABFC), color(0xA5B4FC)], glintStrength: 1)
    sparkles(ctx, [(tip.x + 6, tip.y - 4, 30), (770, 780, 20), (250, 250, 16)], tint: color(0xF0ABFC))
}

// C. Night Sky
render("nib-c-night-sky") { ctx in
    base(ctx, top: color(0x6D28D9), mid: color(0x3B0F7A), bottom: color(0x14072B), rim: color(0xC4B5FD))
    // Star dust.
    let stars: [(CGFloat, CGFloat, CGFloat)] = [(220, 760, 4), (300, 830, 3), (760, 820, 5), (820, 690, 3), (200, 560, 3),
                                                (850, 520, 4), (260, 380, 3), (780, 330, 3), (360, 700, 2), (690, 760, 2)]
    for (x, y, r) in stars {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 3, color: color(0xF5D0FE).cgColor)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        ctx.restoreGState()
    }
    let rot: CGFloat = 0, off = CGPoint(x: 0, y: 30), sc: CGFloat = 0.82
    let tip = tipPoint(rotation: rot, offset: off, scale: sc)
    // A short glowing line being written.
    let line = NSBezierPath()
    line.move(to: CGPoint(x: tip.x - 200, y: tip.y - 20))
    line.curve(to: tip, controlPoint1: CGPoint(x: tip.x - 130, y: tip.y + 40), controlPoint2: CGPoint(x: tip.x - 60, y: tip.y - 50))
    inkStroke(ctx, line, width: 20)
    inkGlow(ctx, at: tip, radius: 150)
    nib(ctx, rotation: rot, offset: off, scale: sc, glint: [color(0xF0ABFC), color(0x818CF8)], glintStrength: 0.75)
    sparkles(ctx, [(tip.x, tip.y - 4, 34), (720, 760, 18)], tint: color(0xF0ABFC))
}
print("rendered nib variations")
