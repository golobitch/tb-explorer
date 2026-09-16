import AppKit
import CoreGraphics

// Renders the TigerBeetle Explorer app icon at 1024×1024 following the macOS
// icon template: an 824pt rounded tile centered on the canvas with a drop shadow.

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("context") }

// CoreGraphics origin is bottom-left.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x1A1D24))
ctx.fillPath()
ctx.restoreGState()

// Tile: graphite vertical gradient.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let tileGradient = CGGradient(
    colorsSpace: space,
    colors: [rgb(0x343A46), rgb(0x1C1F27), rgb(0x111318)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Faint amber "tiger stripes" across the lower-right corner.
ctx.setLineCap(.round)
for (i, alpha) in [0.10, 0.07, 0.05].enumerated() {
    let offset = CGFloat(i) * 70
    ctx.setStrokeColor(rgb(0xF5A524, alpha))
    ctx.setLineWidth(34)
    ctx.move(to: CGPoint(x: 600 + offset, y: 80))
    ctx.addLine(to: CGPoint(x: 960, y: 440 - offset))
    ctx.strokePath()
}

// Top inner highlight.
let highlight = CGGradient(
    colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 700), options: [])
ctx.restoreGState()

// Hairline border for definition on dark backgrounds.
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08))
ctx.setLineWidth(4)
ctx.strokePath()

// Magnifying glass.
let lensCenter = CGPoint(x: 462, y: 566)
let lensRadius: CGFloat = 232
let ringWidth: CGFloat = 46

// Lens glass: dark with a slight tint.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
ctx.clip()
let glass = CGGradient(
    colorsSpace: space, colors: [rgb(0x2A303B), rgb(0x161920)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    glass, startCenter: CGPoint(x: lensCenter.x - 60, y: lensCenter.y + 80), startRadius: 0,
    endCenter: lensCenter, endRadius: lensRadius, options: [.drawsAfterEndLocation])

// Ledger rows inside the lens: bullet + bar (debit orange, credit teal, neutral).
let rows: [(y: CGFloat, width: CGFloat, bullet: UInt32, bar: UInt32)] = [
    (lensCenter.y + 88, 210, 0xFF8A3D, 0xE9ECF1),
    (lensCenter.y, 250, 0x2DD4BF, 0xE9ECF1),
    (lensCenter.y - 88, 170, 0x9AA3B2, 0x9AA3B2),
]
for row in rows {
    let bulletX = lensCenter.x - 150
    ctx.setFillColor(rgb(row.bullet))
    ctx.fillEllipse(in: CGRect(x: bulletX - 26, y: row.y - 26, width: 52, height: 52))
    let bar = CGRect(x: bulletX + 52, y: row.y - 20, width: row.width, height: 40)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 20, cornerHeight: 20, transform: nil))
    ctx.setFillColor(rgb(row.bar, row.bar == 0x9AA3B2 ? 0.55 : 0.92))
    ctx.fillPath()
}

// Glass reflection.
ctx.setFillColor(rgb(0xFFFFFF, 0.06))
ctx.saveGState()
ctx.translateBy(x: lensCenter.x - 120, y: lensCenter.y + 150)
ctx.rotate(by: .pi / 5)
ctx.fillEllipse(in: CGRect(x: -95, y: -38, width: 190, height: 76))
ctx.restoreGState()
ctx.restoreGState()

// Handle: a single rounded amber stroke with a soft shadow, drawn under the ring.
// The start is flat and sits on the ring's centerline so the ring (drawn next) hides the joint;
// only the far end is rounded.
let handleStart = CGPoint(
    x: lensCenter.x + lensRadius * cos(-.pi / 4),
    y: lensCenter.y + lensRadius * sin(-.pi / 4))
let handleEnd = CGPoint(x: 800, y: 228)
let handleWidth: CGFloat = 74
let handle = CGMutablePath()
handle.move(to: handleStart)
handle.addLine(to: handleEnd)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.45))
// Fill the shaft and the rounded tip separately inside one layer so they union
// (a single combined path would cancel where they overlap) and share one shadow.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(0xEE9A1F))
ctx.addPath(handle.copy(strokingWithWidth: handleWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10))
ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: handleEnd.x - handleWidth / 2, y: handleEnd.y - handleWidth / 2, width: handleWidth, height: handleWidth))
ctx.endTransparencyLayer()
ctx.restoreGState()

// Lens ring: amber gradient stroke.
ctx.saveGState()
let ringRect = CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2)
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x000000, 0.4))
ctx.addEllipse(in: ringRect)
ctx.setLineWidth(ringWidth)
ctx.replacePathWithStrokedPath()
ctx.clip()
let ringGradient = CGGradient(
    colorsSpace: space, colors: [rgb(0xFFC45C), rgb(0xF5A524), rgb(0xC9761A)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(
    ringGradient, start: CGPoint(x: lensCenter.x - lensRadius, y: lensCenter.y + lensRadius),
    end: CGPoint(x: lensCenter.x + lensRadius, y: lensCenter.y - lensRadius), options: [])
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
