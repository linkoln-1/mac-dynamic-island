import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 64
let canvas = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: canvas, cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.24, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: []
)

let pill = CGRect(x: 232, y: 428, width: 560, height: 168)
let pillPath = CGPath(roundedRect: pill, cornerWidth: 84, cornerHeight: 84, transform: nil)

ctx.setShadow(
    offset: .zero, blur: 110,
    color: NSColor(calibratedRed: 0.45, green: 0.72, blue: 1.0, alpha: 0.55).cgColor
)
ctx.setFillColor(NSColor.black.cgColor)
ctx.addPath(pillPath)
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.setStrokeColor(NSColor(white: 1, alpha: 0.9).cgColor)
ctx.setLineWidth(12)
ctx.addPath(pillPath)
ctx.strokePath()

func dot(_ x: CGFloat, _ color: NSColor, radius: CGFloat = 30) {
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: CGRect(x: x - radius, y: 512 - radius, width: radius * 2, height: radius * 2))
}
dot(360, NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1))
dot(512, NSColor(white: 0.95, alpha: 1))
dot(664, NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.25, alpha: 1))

func sparkle(center: CGPoint, outer: CGFloat, inner: CGFloat) {
    let path = CGMutablePath()
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4 - .pi / 2
        let radius = index % 2 == 0 ? outer : inner
        let point = CGPoint(
            x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius
        )
        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    ctx.setFillColor(NSColor(white: 1, alpha: 0.95).cgColor)
    ctx.setShadow(offset: .zero, blur: 40, color: NSColor(white: 1, alpha: 0.6).cgColor)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}
sparkle(center: CGPoint(x: 790, y: 700), outer: 74, inner: 26)
sparkle(center: CGPoint(x: 268, y: 322), outer: 44, inner: 16)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("written: \(out)")
