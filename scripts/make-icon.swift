// Renders the app icon: a globe with the Greenwich meridian highlighted and clock hands on top.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Background tile, following Apple's macOS icon grid (824pt body inset in a 1024 canvas).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
rgb(0x14254F).setFill()
tilePath.fill()
ctx.restoreGState()
tilePath.addClip()
NSGradient(starting: rgb(0x2B4C8C), ending: rgb(0x0E1A3A))!.draw(in: tile, angle: -90)

let c = NSPoint(x: size / 2, y: size / 2)
let r: CGFloat = 290

// Globe: outline, latitude and longitude lines.
let grid = rgb(0xFFFFFF, 0.22)
grid.setStroke()
for dx in [0.35, 0.7] as [CGFloat] {
    let e = NSBezierPath(ovalIn: NSRect(x: c.x - r * dx, y: c.y - r, width: 2 * r * dx, height: 2 * r))
    e.lineWidth = 8
    e.stroke()
}
for lat in [-0.5, 0, 0.5] as [CGFloat] {
    let y = c.y + r * lat
    let half = r * sqrt(1 - lat * lat)
    let l = NSBezierPath()
    l.move(to: NSPoint(x: c.x - half, y: y))
    l.line(to: NSPoint(x: c.x + half, y: y))
    l.lineWidth = 8
    l.stroke()
}
let rim = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
rim.lineWidth = 16
rgb(0xFFFFFF, 0.9).setStroke()
rim.stroke()

// The meridian itself, in amber.
let amber = rgb(0xF5A623)
let meridian = NSBezierPath()
meridian.move(to: NSPoint(x: c.x, y: c.y - r - 40))
meridian.line(to: NSPoint(x: c.x, y: c.y + r + 40))
meridian.lineWidth = 18
meridian.lineCapStyle = .round
amber.setStroke()
meridian.stroke()

// Clock hands at roughly 10:10.
func hand(angleDeg: CGFloat, length: CGFloat, width: CGFloat) {
    let a = angleDeg * .pi / 180
    let p = NSBezierPath()
    p.move(to: c)
    p.line(to: NSPoint(x: c.x + cos(a) * length, y: c.y + sin(a) * length))
    p.lineWidth = width
    p.lineCapStyle = .round
    p.stroke()
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.4).cgColor)
NSColor.white.setStroke()
hand(angleDeg: 150, length: 165, width: 34)  // hour
hand(angleDeg: 30, length: 235, width: 24)   // minute
ctx.restoreGState()
amber.setFill()
NSBezierPath(ovalIn: NSRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)).fill()
rgb(0x0E1A3A).setFill()
NSBezierPath(ovalIn: NSRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)).fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
