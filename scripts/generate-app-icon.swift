#!/usr/bin/swift
// Generates Popskill app icon PNGs + .icns from a single procedural canvas.
// Run: swift scripts/generate-app-icon.swift
// Outputs to swift-app/Resources/AppIcon.appiconset/ + AppIcon.icns
//
// Design: macOS-style adaptation of the prototype LedgerMark:
// a near-black rounded square with two white linked capability nodes.
// The geometry intentionally follows tmp/popskill-handoff/.../v1-ledger.jsx:
// rect 18x18 rx=5, circles at 6.4/6.4 and 11.6/11.6, joined by a diagonal.

import AppKit
import Foundation

let outDir = "swift-app/Resources/AppIcon.appiconset"
let icnsOut = "swift-app/Resources/AppIcon.icns"

// macOS app icon sizes per AppIconSet contract.
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func render(size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create icon bitmap")
    }
    bitmap.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.shouldAntialias = true
    defer { NSGraphicsContext.restoreGraphicsState() }

    let ctx = graphics.cgContext
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // macOS Big Sur+ icon: rounded square ~22.37% radius.
    let radius = s * 0.2237
    let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                            xRadius: radius, yRadius: radius)
    path.addClip()

    // Prototype mark base: solid near-black, matching the design canvas.
    NSColor(calibratedWhite: 0.067, alpha: 1.0).setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018),
                  blur: s * 0.04,
                  color: NSColor.black.withAlphaComponent(0.38).cgColor)

    let markColor = NSColor(white: 1.0, alpha: 0.96)
    markColor.setStroke()

    let line = NSBezierPath()
    line.lineWidth = s * 0.074
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: s * 0.438, y: s * 0.438))
    line.line(to: NSPoint(x: s * 0.562, y: s * 0.562))
    line.stroke()

    let nodeRadius = s * 0.106
    let nodeStroke = s * 0.074
    func drawNode(cx: CGFloat, cy: CGFloat) {
        let node = NSBezierPath(ovalIn: NSRect(
            x: cx - nodeRadius,
            y: cy - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        ))
        node.lineWidth = nodeStroke
        node.stroke()
    }

    drawNode(cx: s * 0.356, cy: s * 0.356)
    drawNode(cx: s * 0.644, cy: s * 0.644)
    ctx.restoreGState()

    // Quiet inner rim keeps the dark tile crisp on light and dark wallpapers.
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    path.lineWidth = max(1, s * 0.012)
    path.stroke()

    return bitmap
}

func writePNG(bitmap: NSBitmapImageRep, path: String) throws {
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icongen", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, size) in sizes {
    let img = render(size: size)
    let path = "\(outDir)/\(name)"
    try writePNG(bitmap: img, path: path)
    print("rendered \(path)")
}

// Write Contents.json so xcrun --sdk macosx actool / iconutil knows the layout.
let contentsJSON = """
{
  "images": [
    {"size":"16x16","idiom":"mac","filename":"icon_16x16.png","scale":"1x"},
    {"size":"16x16","idiom":"mac","filename":"icon_16x16@2x.png","scale":"2x"},
    {"size":"32x32","idiom":"mac","filename":"icon_32x32.png","scale":"1x"},
    {"size":"32x32","idiom":"mac","filename":"icon_32x32@2x.png","scale":"2x"},
    {"size":"128x128","idiom":"mac","filename":"icon_128x128.png","scale":"1x"},
    {"size":"128x128","idiom":"mac","filename":"icon_128x128@2x.png","scale":"2x"},
    {"size":"256x256","idiom":"mac","filename":"icon_256x256.png","scale":"1x"},
    {"size":"256x256","idiom":"mac","filename":"icon_256x256@2x.png","scale":"2x"},
    {"size":"512x512","idiom":"mac","filename":"icon_512x512.png","scale":"1x"},
    {"size":"512x512","idiom":"mac","filename":"icon_512x512@2x.png","scale":"2x"}
  ],
  "info": {"version":1,"author":"popskill"}
}
"""
try contentsJSON.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)

// Generate .icns via iconutil. iconutil needs a specific .iconset folder layout.
let iconsetTmp = "/tmp/Popskill.iconset"
try? fm.removeItem(atPath: iconsetTmp)
try fm.createDirectory(atPath: iconsetTmp, withIntermediateDirectories: true)
for (name, _) in sizes {
    let src = "\(outDir)/\(name)"
    let dst = "\(iconsetTmp)/\(name)"
    try fm.copyItem(atPath: src, toPath: dst)
}

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments = ["-c", "icns", iconsetTmp, "-o", icnsOut]
try proc.run()
proc.waitUntilExit()
print("wrote \(icnsOut) (status=\(proc.terminationStatus))")
