// Generates Notchly's app icon: Resources/AppIcon.png (1024), Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

let S: CGFloat = 1024
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }

/// Apple-style continuous-corner squircle.
func squircle(_ r: CGRect, n: CGFloat = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.line(to: CGPoint(x: x, y: y)) }
    }
    p.close()
    return p
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: S, height: S)
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

// Drop shadow under the whole icon
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.45).cgColor)
rgb(10, 10, 24).setFill(); shape.fill()
ctx.restoreGState()

// Clip to the squircle for everything inside
ctx.saveGState()
shape.addClip()

// Base: deep indigo -> near black
NSGradient(colors: [rgb(58, 56, 140), rgb(24, 22, 66), rgb(8, 8, 22)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -90)
// Colored glows
NSGradient(colors: [rgb(255, 70, 150, 0.55), rgb(255, 70, 150, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(fromCenter: CGPoint(x: 780, y: 190), radius: 0, toCenter: CGPoint(x: 780, y: 190), radius: 420, options: [])
NSGradient(colors: [rgb(40, 190, 255, 0.50), rgb(40, 190, 255, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(fromCenter: CGPoint(x: 250, y: 260), radius: 0, toCenter: CGPoint(x: 250, y: 260), radius: 440, options: [])

// Soft glossy highlight (radial, no hard edge)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0.06), NSColor.white.withAlphaComponent(0)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    .draw(fromCenter: CGPoint(x: 512, y: 960), radius: 0, toCenter: CGPoint(x: 512, y: 960), radius: 620, options: [])
// Faint bottom bounce light (radial, soft)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)], atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(fromCenter: CGPoint(x: 512, y: 80), radius: 0, toCenter: CGPoint(x: 512, y: 80), radius: 420, options: [])

// The island: a black pill hanging from the top edge (the notch growing into a Dynamic-Island style panel)
let islandW: CGFloat = 560, islandH: CGFloat = 330
let island = CGRect(x: S / 2 - islandW / 2, y: body.maxY - islandH, width: islandW, height: islandH)
let ip = NSBezierPath()
let r: CGFloat = 120
ip.move(to: CGPoint(x: island.minX - 40, y: island.maxY + 2))
ip.curve(to: CGPoint(x: island.minX, y: island.maxY - 40), controlPoint1: CGPoint(x: island.minX - 6, y: island.maxY + 2), controlPoint2: CGPoint(x: island.minX, y: island.maxY - 6))
ip.line(to: CGPoint(x: island.minX, y: island.minY + r))
ip.curve(to: CGPoint(x: island.minX + r, y: island.minY), controlPoint1: CGPoint(x: island.minX, y: island.minY + r * 0.45), controlPoint2: CGPoint(x: island.minX + r * 0.45, y: island.minY))
ip.line(to: CGPoint(x: island.maxX - r, y: island.minY))
ip.curve(to: CGPoint(x: island.maxX, y: island.minY + r), controlPoint1: CGPoint(x: island.maxX - r * 0.45, y: island.minY), controlPoint2: CGPoint(x: island.maxX, y: island.minY + r * 0.45))
ip.line(to: CGPoint(x: island.maxX, y: island.maxY - 40))
ip.curve(to: CGPoint(x: island.maxX + 40, y: island.maxY + 2), controlPoint1: CGPoint(x: island.maxX, y: island.maxY - 6), controlPoint2: CGPoint(x: island.maxX + 6, y: island.maxY + 2))
ip.line(to: CGPoint(x: island.minX - 40, y: island.maxY + 2))
ip.close()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: NSColor.black.withAlphaComponent(0.7).cgColor)
rgb(0, 0, 0).setFill(); ip.fill()
ctx.restoreGState()
NSGradient(colors: [rgb(14, 14, 20), rgb(0, 0, 0)], atLocations: [0, 1], colorSpace: .sRGB)!.draw(in: ip, angle: -90)
// island rim light
ctx.saveGState(); ip.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.07), NSColor.white.withAlphaComponent(0)], atLocations: [0, 1], colorSpace: .sRGB)!
    .draw(in: CGRect(x: island.minX, y: island.midY, width: islandW, height: islandH / 2), angle: -90)
ctx.restoreGState()
ip.lineWidth = 3; NSColor.white.withAlphaComponent(0.10).setStroke(); ip.stroke()

// Equalizer bars inside the island
let heights: [CGFloat] = [70, 130, 190, 110, 160]
let barW: CGFloat = 40, gap: CGFloat = 26
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = S / 2 - totalW / 2
let cols = [rgb(40, 200, 255), rgb(90, 160, 255), rgb(170, 110, 255), rgb(240, 90, 200), rgb(255, 110, 140)]
for (i, h) in heights.enumerated() {
    let bar = CGRect(x: x, y: island.minY + 66 + (190 - h) / 2, width: barW, height: h)
    let bp = NSBezierPath(roundedRect: bar, xRadius: barW / 2, yRadius: barW / 2)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26, color: cols[i].withAlphaComponent(0.8).cgColor)
    cols[i].setFill(); bp.fill()
    ctx.restoreGState()
    ctx.saveGState(); bp.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0)], atLocations: [0, 0.6], colorSpace: .sRGB)!
        .draw(in: bar, angle: -90)
    ctx.restoreGState()
    x += barW + gap
}

ctx.restoreGState()   // end squircle clip

// Edge highlight + inner shadow ring
shape.lineWidth = 3
NSColor.white.withAlphaComponent(0.22).setStroke()
ctx.saveGState(); shape.addClip(); shape.lineWidth = 6; shape.stroke(); ctx.restoreGState()

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
try! png.write(to: root.appendingPathComponent("AppIcon.png"))

// iconset -> icns
let set = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
func resized(_ px: Int) -> Data {
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return r.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! resized(px).write(to: set.appendingPathComponent("icon_\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
print("icon written, iconutil exit \(p.terminationStatus)")
