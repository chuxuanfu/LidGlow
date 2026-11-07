#!/usr/bin/env swift
// Original LidGlow artwork. Run from the repository root:
//   swift tools/generate-icon.swift
// Uses only macOS AppKit and iconutil; no downloaded assets or dependencies.
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: 1024 - y - h, width: w, height: h)
}
func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: 1024 - y) }
func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, w, h), xRadius: r, yRadius: r)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
         let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "LidGlow.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let cg = graphics.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.setShouldAntialias(true)

    let body = roundRect(80, 80, 864, 864, 192)
    NSGraphicsContext.saveGraphicsState()
    let dropShadow = NSShadow()
    dropShadow.shadowColor = color(0x020711, 0.32)
    dropShadow.shadowOffset = NSSize(width: 0, height: -12)
    dropShadow.shadowBlurRadius = 28
    dropShadow.set()
    color(0x0A1321).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: color(0x1B3044), ending: color(0x090F1D))!
        .draw(from: point(280, 80), to: point(740, 944), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
    color(0x9BB9CF, 0.18).setStroke()
    body.lineWidth = 3
    body.stroke()

    // Broad, quiet halo makes the light read as a source, not a painted dash.
    NSGraphicsContext.saveGraphicsState()
    let halo = NSShadow()
    halo.shadowColor = color(0x42DEFA, 0.55)
    halo.shadowOffset = .zero
    halo.shadowBlurRadius = 90
    halo.set()
    color(0x63E6FB, 0.24).setFill()
    roundRect(344, 446, 336, 52, 26).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Laptop lid. Slightly heavier small-size strokes are deliberate optical corrections.
    let lid = roundRect(246, 278, 532, 366, 34)
    lid.lineWidth = size <= 32 ? 48 : 30
    color(0xC8DBE7, 0.96).setStroke()
    lid.stroke()

    let base = NSBezierPath()
    base.move(to: point(202, 694))
    base.line(to: point(822, 694))
    base.curve(to: point(778, 728), controlPoint1: point(818, 716), controlPoint2: point(798, 728))
    base.line(to: point(246, 728))
    base.curve(to: point(202, 694), controlPoint1: point(226, 728), controlPoint2: point(206, 716))
    base.close()
    color(0xC8DBE7, 0.93).setFill()
    base.fill()

    let barHeight: CGFloat = size <= 32 ? 44 : 28
    let bar = roundRect(352, 472 - barHeight / 2, 320, barHeight, barHeight / 2)
    NSGraphicsContext.saveGraphicsState()
    let light = NSShadow()
    light.shadowColor = color(0x5CEAFF, 0.95)
    light.shadowOffset = .zero
    light.shadowBlurRadius = 36
    light.set()
    color(0x83F1FF).setFill()
    bar.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0xB5FAFF).setFill()
    roundRect(372, 466, 280, 8, 4).fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LidGlow.Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG"])
    }
    return data
}

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in entries {
    try drawIcon(size: size).write(to: iconset.appendingPathComponent(name), options: .atomic)
}
try drawIcon(size: 1024).write(to: assets.appendingPathComponent("AppIcon.png"), options: .atomic)

// Scalable, editable companion to the native AppKit drawing above.
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
  <title id="title">LidGlow</title>
  <desc id="desc">A silver laptop lid with a cyan light on a dark navy rounded square.</desc>
  <defs>
    <linearGradient id="navy" x1="0.2" y1="0" x2="0.8" y2="1"><stop stop-color="#1B3044"/><stop offset="1" stop-color="#090F1D"/></linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#020711" flood-opacity=".32"/></filter>
    <filter id="halo" x="-70%" y="-400%" width="240%" height="900%"><feGaussianBlur stdDeviation="40"/></filter>
    <filter id="glow" x="-30%" y="-300%" width="160%" height="700%"><feGaussianBlur stdDeviation="16"/></filter>
  </defs>
  <rect x="80" y="80" width="864" height="864" rx="192" fill="url(#navy)" filter="url(#shadow)"/>
  <rect x="80" y="80" width="864" height="864" rx="192" fill="none" stroke="#9BB9CF" stroke-opacity=".18" stroke-width="3"/>
  <rect x="344" y="446" width="336" height="52" rx="26" fill="#42DEFA" opacity=".55" filter="url(#halo)"/>
  <rect x="246" y="278" width="532" height="366" rx="34" fill="none" stroke="#C8DBE7" stroke-opacity=".96" stroke-width="30"/>
  <path d="M202 694H822C818 716 798 728 778 728H246C226 728 206 716 202 694Z" fill="#C8DBE7" fill-opacity=".93"/>
  <rect x="352" y="458" width="320" height="28" rx="14" fill="#5CEAFF" filter="url(#glow)"/>
  <rect x="352" y="458" width="320" height="28" rx="14" fill="#83F1FF"/>
  <rect x="372" y="466" width="280" height="8" rx="4" fill="#B5FAFF"/>
</svg>
"""
try svg.write(to: assets.appendingPathComponent("LidGlow.svg"), atomically: true, encoding: .utf8)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
print("Generated Assets/AppIcon.icns, Assets/AppIcon.png, Assets/LidGlow.svg and all 10 iconset representations.")
