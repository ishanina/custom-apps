// Renders Resources/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // macOS icon grid: 824/1024 body with ~185/1024 corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0, 0, 0, 0.45))
    ctx.addPath(path); ctx.setFillColor(color(0.1, 0.1, 0.11)); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [color(0.17, 0.17, 0.19), color(0.06, 0.06, 0.07)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Soft volt glow
    let glow = CGGradient(colorsSpace: cs, colors: [color(0.84, 1, 0.28, 0.22), color(0.84, 1, 0.28, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                           endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: body.width * 0.55, options: [])
    ctx.restoreGState()

    let center = CGPoint(x: s / 2, y: s / 2)
    let ringR = body.width * 0.3
    let lw = body.width * 0.085

    // Ring track
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(1, 1, 1, 0.09))
    ctx.addArc(center: center, radius: ringR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Segmented progress ring in the four step colors, then volt.
    let segments: [(CGColor, CGFloat)] = [
        (color(0.47, 0.52, 1.0), 0.17),
        (color(1.0, 0.60, 0.22), 0.17),
        (color(0.36, 0.80, 0.97), 0.11),
        (color(1.0, 0.36, 0.66), 0.13),
        (color(0.84, 1.0, 0.28), 0.17),
    ]
    let gap: CGFloat = 0.21 // radians per side; must exceed the round-cap overhang
    var start = CGFloat.pi / 2 // 12 o'clock, going clockwise
    for (c, frac) in segments {
        let sweep = frac * 2 * .pi
        ctx.setStrokeColor(c)
        ctx.addArc(center: center, radius: ringR, startAngle: start - gap, endAngle: start - sweep + gap, clockwise: true)
        ctx.strokePath()
        start -= sweep
    }

    // Play triangle in volt
    let t = body.width * 0.16
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: center.x - t * 0.42, y: center.y + t * 0.6))
    tri.addLine(to: CGPoint(x: center.x + t * 0.62, y: center.y))
    tri.addLine(to: CGPoint(x: center.x - t * 0.42, y: center.y - t * 0.6))
    tri.closeSubpath()
    ctx.saveGState()
    ctx.addPath(tri)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(t * 0.22)
    ctx.setStrokeColor(color(0.84, 1.0, 0.28))
    ctx.setFillColor(color(0.84, 1.0, 0.28))
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try! render(1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print("Wrote \(out.path)")
