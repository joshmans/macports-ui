// Renders the 1024x1024 app icon: usage: swift make-icon.swift out.png
import AppKit

let S = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt tile centred in 1024 with a soft shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
NSColor.black.setFill(); tilePath.fill()
ctx.restoreGState()
tilePath.addClip()
NSGradient(colors: [NSColor(red: 0.30, green: 0.52, blue: 1.0, alpha: 1), NSColor(red: 0.30, green: 0.18, blue: 0.62, alpha: 1)])!
    .draw(in: tile, angle: -60)
// top sheen
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)

// Isometric cube (a package box)
let c = CGPoint(x: 512, y: 500), r = 250.0
func pt(_ ang: Double, _ rad: Double = r) -> CGPoint {
    CGPoint(x: c.x + rad * cos(ang * .pi / 180), y: c.y + rad * sin(ang * .pi / 180))
}
let top = pt(90), ur = pt(30), lr = pt(-30), bot = pt(-90), ll = pt(-150), ul = pt(150)
func face(_ pts: [CGPoint], _ color: NSColor) {
    let p = NSBezierPath(); p.move(to: pts[0]); pts.dropFirst().forEach { p.line(to: $0) }; p.close()
    p.lineJoinStyle = .round; color.setFill(); p.fill()
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 30, color: NSColor(white: 0, alpha: 0.35).cgColor)
face([top, ur, lr, bot, ll, ul], .white)
ctx.restoreGState()
let inset = 10.0
func shrink(_ p: CGPoint, toward q: CGPoint) -> CGPoint {
    let dx = q.x - p.x, dy = q.y - p.y, d = hypot(dx, dy); return CGPoint(x: p.x + dx / d * inset, y: p.y + dy / d * inset)
}
face([top, ur, c, ul], NSColor(white: 1.0, alpha: 1))                                    // top
face([ul, c, bot, ll], NSColor(red: 0.84, green: 0.88, blue: 1.0, alpha: 1))             // left
face([c, ur, lr, bot], NSColor(red: 0.66, green: 0.73, blue: 0.98, alpha: 1))            // right
// seams
ctx.setStrokeColor(NSColor(red: 0.45, green: 0.50, blue: 0.85, alpha: 0.55).cgColor)
ctx.setLineWidth(5); ctx.setLineCap(.round)
for (a, b) in [(ul, c), (ur, c), (c, bot)] { ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath() }

// Gear on the left face, sheared into the face plane
func gear(center: CGPoint, outer: Double, inner: Double, teeth: Int, hole: Double) -> NSBezierPath {
    let p = NSBezierPath()
    let step = 2 * Double.pi / Double(teeth)
    for i in 0..<teeth {
        let a = Double(i) * step
        let pts: [(Double, Double)] = [(a - step * 0.30, inner), (a - step * 0.17, outer), (a + step * 0.17, outer), (a + step * 0.30, inner)]
        for (j, q) in pts.enumerated() {
            let pt = CGPoint(x: center.x + q.1 * cos(q.0), y: center.y + q.1 * sin(q.0))
            if i == 0 && j == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
    }
    p.close()
    p.appendOval(in: NSRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
    p.windingRule = .evenOdd
    return p
}
ctx.saveGState()
// left face basis: x axis along ul->c direction (down-right), y axis vertical
let lc = CGPoint(x: (ul.x + c.x + bot.x + ll.x) / 4, y: (ul.y + c.y + bot.y + ll.y) / 4)
let t = CGAffineTransform(a: 0.866, b: -0.5, c: 0, d: 1, tx: 0, ty: 0)
ctx.translateBy(x: lc.x, y: lc.y); ctx.concatenate(t)
let g = gear(center: .zero, outer: 105, inner: 82, teeth: 10, hole: 34)
NSColor(red: 0.27, green: 0.28, blue: 0.70, alpha: 0.95).setFill(); g.fill()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
