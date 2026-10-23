// Draws the ProPresenter Voice Remote app icon: a slide with a "next" chevron
// and a microphone, on the standard macOS icon grid. Usage: swift make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

// Background tile: 824 px rounded square with a soft drop shadow (macOS grid).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
rgb(0x1B1F4A).setFill(); tilePath.fill()
ctx.restoreGState()
ctx.saveGState()
tilePath.addClip()
NSGradient(colors: [rgb(0x2B3A9E), rgb(0x161A3D)])!.draw(in: tile, angle: -90)
ctx.restoreGState()

// The slide: a screen with a 16:9-ish face, slightly up and left.
let slide = NSRect(x: 190, y: 430, width: 560, height: 360)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.3).cgColor)
rgb(0xF4F6FF).setFill()
NSBezierPath(roundedRect: slide, xRadius: 44, yRadius: 44).fill()
ctx.restoreGState()

// "Next" chevron on the slide.
let chev = NSBezierPath()
chev.move(to: NSPoint(x: 410, y: 700))
chev.line(to: NSPoint(x: 520, y: 610))
chev.line(to: NSPoint(x: 410, y: 520))
chev.lineWidth = 58
chev.lineCapStyle = .round
chev.lineJoinStyle = .round
rgb(0x2B3A9E).setStroke(); chev.stroke()

// Microphone, lower right, overlapping the slide corner.
let accent = rgb(0xFF8A3D)
let cx: CGFloat = 690
// Ring behind the mic so it separates from the slide.
rgb(0x161A3D).setFill()
NSBezierPath(ovalIn: NSRect(x: cx - 170, y: 175, width: 340, height: 340)).fill()
// Capsule head.
accent.setFill()
NSBezierPath(roundedRect: NSRect(x: cx - 62, y: 300, width: 124, height: 190), xRadius: 62, yRadius: 62).fill()
// Cradle arc.
let cradle = NSBezierPath()
cradle.appendArc(withCenter: NSPoint(x: cx, y: 375), radius: 102, startAngle: 200, endAngle: 340)
cradle.lineWidth = 30; cradle.lineCapStyle = .round
accent.setStroke(); cradle.stroke()
// Stem and base.
let stem = NSBezierPath()
stem.move(to: NSPoint(x: cx, y: 273)); stem.line(to: NSPoint(x: cx, y: 225))
stem.move(to: NSPoint(x: cx - 55, y: 225)); stem.line(to: NSPoint(x: cx + 55, y: 225))
stem.lineWidth = 30; stem.lineCapStyle = .round
stem.stroke()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
