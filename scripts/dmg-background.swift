// Renders the DMG window background: usage: swift dmg-background.swift out.png
// Window is 660x400 points; the PNG is 2x (1320x800) tagged 144 dpi so Finder scales it.
import AppKit

let w = 660.0, h = 400.0, scale = 2.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background gradient
let grad = NSGradient(colors: [NSColor(red: 0.10, green: 0.14, blue: 0.27, alpha: 1),
                               NSColor(red: 0.22, green: 0.16, blue: 0.42, alpha: 1)])!
grad.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -35)

// Soft glow behind each icon slot
for cx in [165.0, 495.0] {
    let g = NSGradient(colors: [NSColor(white: 1, alpha: 0.16), NSColor(white: 1, alpha: 0)])!
    g.draw(fromCenter: NSPoint(x: cx, y: 215), radius: 0, toCenter: NSPoint(x: cx, y: 215), radius: 110, options: [])
}

// Light pills under the icon labels: Finder draws them in dark text regardless of appearance.
for cx in [165.0, 495.0] {
    let pill = NSBezierPath(roundedRect: NSRect(x: cx - 62, y: 98, width: 124, height: 26), xRadius: 13, yRadius: 13)
    NSColor(white: 1, alpha: 0.88).setFill(); pill.fill()
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: p]
    (s as NSString).draw(in: NSRect(x: 0, y: y, width: w, height: size + 8), withAttributes: a)
}
text("MacPorts UI", size: 26, weight: .semibold, alpha: 0.95, y: 338)
text("Drag the app into Applications to install", size: 13, weight: .regular, alpha: 0.65, y: 312)

// Arrow between the two slots
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.8).cgColor)
ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 280, y: 215)); ctx.addLine(to: CGPoint(x: 380, y: 215)); ctx.strokePath()
ctx.move(to: CGPoint(x: 358, y: 237)); ctx.addLine(to: CGPoint(x: 382, y: 215)); ctx.addLine(to: CGPoint(x: 358, y: 193)); ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
