#!/usr/bin/swift
// Generates Popskill app icon PNGs + .icns from a single procedural canvas.
// Run: swift scripts/generate-app-icon.swift
// Outputs to swift-app/Resources/AppIcon.appiconset/ + AppIcon.icns
//
// Design: rounded-square macOS-style icon, orange→purple diagonal gradient
// background (matches the popSectionOrange / popSectionPurple tokens), 3x3
// dot matrix in white at the center to evoke the "capabilities × tools"
// matrix that's the app's headline visual.

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

func render(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    defer { image.unlockFocus() }

    let ctx = NSGraphicsContext.current!.cgContext
    // macOS Big Sur+ icon: rounded square ~22.37% radius.
    let radius = s * 0.2237
    let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                            xRadius: radius, yRadius: radius)
    path.addClip()

    // Diagonal gradient: warm orange → muted purple, matches the in-app
    // section accent palette so the icon visually anchors the same brand.
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.20, alpha: 1.0),
        NSColor(calibratedRed: 0.70, green: 0.30, blue: 0.85, alpha: 1.0),
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -45)

    // 3x3 dot matrix in soft white. Dots are slightly translucent so the
    // gradient bleeds through and the icon feels less like flat clipart.
    let dotColor = NSColor(white: 1.0, alpha: 0.92)
    dotColor.setFill()

    let dotSize = s * 0.16
    let spacing = s * 0.085
    let gridWidth = dotSize * 3 + spacing * 2
    let originX = (s - gridWidth) / 2
    let originY = (s - gridWidth) / 2
    for row in 0..<3 {
        for col in 0..<3 {
            let x = originX + CGFloat(col) * (dotSize + spacing)
            let y = originY + CGFloat(row) * (dotSize + spacing)
            let dot = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: dotSize, height: dotSize),
                                   xRadius: dotSize * 0.32, yRadius: dotSize * 0.32)
            dot.fill()
        }
    }

    // Subtle inner highlight along the top edge — gives the icon a hint of
    // depth without going full skeuomorphic.
    let highlight = NSGradient(colors: [
        NSColor(white: 1.0, alpha: 0.22),
        NSColor(white: 1.0, alpha: 0.0),
    ])!
    highlight.draw(in: NSRect(x: 0, y: s * 0.55, width: s, height: s * 0.45), angle: 90)

    _ = ctx
    return image
}

func writePNG(image: NSImage, path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icongen", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, size) in sizes {
    let img = render(size: size)
    let path = "\(outDir)/\(name)"
    try writePNG(image: img, path: path)
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
