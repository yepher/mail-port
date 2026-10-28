import AppKit
import Foundation

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
        pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MailPort.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 58, y: 58, width: 908, height: 908),
                            xRadius: 207, yRadius: 207)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x061827, alpha: 0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x123B50).setFill()
    tile.fill()
    NSShadow().set()
    NSGradient(starting: color(0x147F87), ending: color(0x10243D))!
        .draw(in: tile, angle: -45)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    color(0x42B5AC, alpha: 0.14).setFill()
    NSBezierPath(ovalIn: NSRect(x: -230, y: 390, width: 930, height: 930)).fill()
    color(0xFFFFFF, alpha: 0.05).setFill()
    NSBezierPath(ovalIn: NSRect(x: 610, y: -310, width: 840, height: 840)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let ring = NSBezierPath(roundedRect: NSRect(x: 66, y: 66, width: 892, height: 892),
                            xRadius: 200, yRadius: 200)
    color(0xFFFFFF, alpha: 0.12).setStroke()
    ring.lineWidth = 3
    ring.stroke()

    let envelope = NSBezierPath(roundedRect: NSRect(x: 208, y: 290, width: 608, height: 438),
                                xRadius: 60, yRadius: 60)
    let envelopeShadow = NSShadow()
    envelopeShadow.shadowColor = color(0x061827, alpha: 0.22)
    envelopeShadow.shadowBlurRadius = 28
    envelopeShadow.shadowOffset = NSSize(width: 0, height: -16)
    envelopeShadow.set()
    color(0xF5FAFB).setFill()
    envelope.fill()
    NSShadow().set()

    let folds = NSBezierPath()
    folds.move(to: NSPoint(x: 233, y: 318))
    folds.line(to: NSPoint(x: 428, y: 508))
    folds.move(to: NSPoint(x: 791, y: 318))
    folds.line(to: NSPoint(x: 596, y: 508))
    folds.lineWidth = 16
    folds.lineCapStyle = .round
    color(0xBCD9DE).setStroke()
    folds.stroke()

    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: 232, y: 685))
    flap.line(to: NSPoint(x: 468, y: 499))
    flap.curve(to: NSPoint(x: 556, y: 499),
               controlPoint1: NSPoint(x: 496, y: 477),
               controlPoint2: NSPoint(x: 528, y: 477))
    flap.line(to: NSPoint(x: 792, y: 685))
    flap.lineWidth = 22
    flap.lineCapStyle = .round
    flap.lineJoinStyle = .round
    color(0x246979).setStroke()
    flap.stroke()

    let accent = NSBezierPath(ovalIn: NSRect(x: 708, y: 669, width: 154, height: 154))
    color(0x0F3D52).setStroke()
    accent.lineWidth = 15
    accent.stroke()
    NSGradient(starting: color(0xFFBF79), ending: color(0xF28A53))!
        .draw(in: accent, angle: -90)
    let horizon = NSBezierPath()
    horizon.move(to: NSPoint(x: 754, y: 745))
    horizon.line(to: NSPoint(x: 808, y: 745))
    horizon.lineWidth = 12
    horizon.lineCapStyle = .round
    color(0xFFFFFF, alpha: 0.95).setStroke()
    horizon.stroke()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MailPort.Icon", code: 2)
    }
    return data
}

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("Usage: make-icon.swift OUTPUT.iconset [FALLBACK.icns]\n", stderr)
    exit(1)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var rendered: [Int: Data] = [:]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let path = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        let pixels = points * scale
        let data = try rendered[pixels] ?? drawIcon(size: pixels)
        rendered[pixels] = data
        try data.write(to: path)
    }
}

if CommandLine.arguments.count == 3 {
    // Modern ICNS records can contain their PNG representation directly.
    // Include both standard-resolution and Retina identifiers.
    let records: [(String, Int)] = [
        ("icp4", 16), ("icp5", 32), ("icp6", 64),
        ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
        ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
    ]
    func uint32(_ value: Int) -> Data {
        var bigEndian = UInt32(value).bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
    var body = Data()
    for (type, pixels) in records {
        let png = rendered[pixels]!
        body.append(contentsOf: type.utf8)
        body.append(uint32(png.count + 8))
        body.append(png)
    }
    var icns = Data("icns".utf8)
    icns.append(uint32(body.count + 8))
    icns.append(body)
    try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
}

