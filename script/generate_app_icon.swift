#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let preview = resources.appendingPathComponent("AppIcon.png")
let icns = resources.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

enum Palette {
    static let polarNight = NSColor(calibratedRed: 46 / 255, green: 52 / 255, blue: 64 / 255, alpha: 1)
    static let frost = NSColor(calibratedRed: 136 / 255, green: 192 / 255, blue: 208 / 255, alpha: 1)
    static let snowStorm = NSColor(calibratedRed: 236 / 255, green: 239 / 255, blue: 244 / 255, alpha: 1)
}

func color(_ base: NSColor, alpha: CGFloat) -> NSColor {
    base.withAlphaComponent(alpha)
}

func rounded(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat, stroke: NSColor, strokeWidth: CGFloat) {
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
    stroke.setStroke()
    path.lineWidth = strokeWidth
    path.stroke()
}

func drawStroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

func linePath(from start: CGPoint, to end: CGPoint) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    return path
}

func drawPromptQuoteGlyph() {
    let glyphShadow = NSShadow()
    glyphShadow.shadowOffset = NSSize(width: 0, height: -22)
    glyphShadow.shadowBlurRadius = 42
    glyphShadow.shadowColor = color(Palette.polarNight, alpha: 0.72)
    glyphShadow.set()

    let bubble = commandBubblePath()
    let chevron = commandChevronPath()
    let cursor = linePath(from: CGPoint(x: 570, y: 443), to: CGPoint(x: 650, y: 443))

    drawStroke(bubble, color: color(Palette.frost, alpha: 0.28), width: 82)
    drawStroke(chevron, color: color(Palette.frost, alpha: 0.28), width: 78)
    drawStroke(cursor, color: color(Palette.frost, alpha: 0.28), width: 78)

    drawStroke(bubble, color: color(Palette.snowStorm, alpha: 0.98), width: 54)
    drawStroke(chevron, color: color(Palette.snowStorm, alpha: 0.98), width: 50)
    drawStroke(cursor, color: color(Palette.snowStorm, alpha: 0.98), width: 50)
}

func commandBubblePath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 324, y: 704))
    path.line(to: CGPoint(x: 700, y: 704))
    path.curve(
        to: CGPoint(x: 780, y: 624),
        controlPoint1: CGPoint(x: 744, y: 704),
        controlPoint2: CGPoint(x: 780, y: 668)
    )
    path.line(to: CGPoint(x: 780, y: 440))
    path.curve(
        to: CGPoint(x: 700, y: 360),
        controlPoint1: CGPoint(x: 780, y: 396),
        controlPoint2: CGPoint(x: 744, y: 360)
    )
    path.line(to: CGPoint(x: 592, y: 360))
    path.line(to: CGPoint(x: 512, y: 280))
    path.line(to: CGPoint(x: 432, y: 360))
    path.line(to: CGPoint(x: 324, y: 360))
    path.curve(
        to: CGPoint(x: 244, y: 440),
        controlPoint1: CGPoint(x: 280, y: 360),
        controlPoint2: CGPoint(x: 244, y: 396)
    )
    path.line(to: CGPoint(x: 244, y: 624))
    path.curve(
        to: CGPoint(x: 324, y: 704),
        controlPoint1: CGPoint(x: 244, y: 668),
        controlPoint2: CGPoint(x: 280, y: 704)
    )
    return path
}

func commandChevronPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 415, y: 585))
    path.line(to: CGPoint(x: 508, y: 512))
    path.line(to: CGPoint(x: 415, y: 439))
    return path
}

func upperWingPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 232, y: 472))
    path.curve(
        to: CGPoint(x: 820, y: 684),
        controlPoint1: CGPoint(x: 420, y: 646),
        controlPoint2: CGPoint(x: 650, y: 748)
    )
    path.curve(
        to: CGPoint(x: 586, y: 574),
        controlPoint1: CGPoint(x: 754, y: 626),
        controlPoint2: CGPoint(x: 672, y: 596)
    )
    path.curve(
        to: CGPoint(x: 320, y: 505),
        controlPoint1: CGPoint(x: 500, y: 552),
        controlPoint2: CGPoint(x: 406, y: 530)
    )
    path.curve(
        to: CGPoint(x: 232, y: 472),
        controlPoint1: CGPoint(x: 276, y: 492),
        controlPoint2: CGPoint(x: 246, y: 480)
    )
    path.close()
    return path
}

func lowerWingPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 300, y: 372))
    path.curve(
        to: CGPoint(x: 820, y: 684),
        controlPoint1: CGPoint(x: 450, y: 474),
        controlPoint2: CGPoint(x: 640, y: 594)
    )
    path.curve(
        to: CGPoint(x: 502, y: 304),
        controlPoint1: CGPoint(x: 728, y: 552),
        controlPoint2: CGPoint(x: 616, y: 388)
    )
    path.curve(
        to: CGPoint(x: 300, y: 372),
        controlPoint1: CGPoint(x: 428, y: 250),
        controlPoint2: CGPoint(x: 356, y: 322)
    )
    path.close()
    return path
}

func centerFoldPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 318, y: 432))
    path.curve(
        to: CGPoint(x: 812, y: 670),
        controlPoint1: CGPoint(x: 486, y: 486),
        controlPoint2: CGPoint(x: 656, y: 574)
    )
    return path
}

func tailPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: 284, y: 398))
    path.curve(
        to: CGPoint(x: 546, y: 512),
        controlPoint1: CGPoint(x: 356, y: 428),
        controlPoint2: CGPoint(x: 456, y: 470)
    )
    return path
}

func renderIcon(size: Int) throws -> NSBitmapImageRep {
    let scale = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(
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
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Could not create drawing context")
    }

    context.scaleBy(x: scale, y: scale)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let iconRect = CGRect(x: 76, y: 76, width: 872, height: 872)
    let iconPath = rounded(iconRect, radius: 206)
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -34)
    shadow.shadowBlurRadius = 64
    shadow.shadowColor = color(Palette.polarNight, alpha: 0.62)
    shadow.set()
    Palette.polarNight.setFill()
    iconPath.fill()
    NSGradient(colors: [
        color(Palette.snowStorm, alpha: 0.055),
        color(Palette.polarNight, alpha: 0.72),
        color(Palette.frost, alpha: 0.070),
        color(Palette.polarNight, alpha: 0.92)
    ])!.draw(in: iconPath, angle: -35)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    iconPath.addClip()
    color(Palette.frost, alpha: 0.07).setFill()
    NSBezierPath(ovalIn: CGRect(x: -80, y: -28, width: 660, height: 660)).fill()
    color(Palette.snowStorm, alpha: 0.045).setFill()
    NSBezierPath(ovalIn: CGRect(x: 450, y: 474, width: 690, height: 520)).fill()

    color(Palette.snowStorm, alpha: 0.16).setStroke()
    iconPath.lineWidth = 2
    iconPath.stroke()

    NSShadow().set()

    drawPromptQuoteGlyph()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    try data.write(to: url)
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    try writePNG(try renderIcon(size: size), to: iconset.appendingPathComponent(name))
}

try writePNG(try renderIcon(size: 1024), to: preview)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

print("Generated \(icns.path)")
