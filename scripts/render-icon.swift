import AppKit
import CoreGraphics

// Renders the TigerBeetle Explorer app icon at 1024×1024: a light ledger sheet with
// debit (orange) and credit (teal) rows and a small amber magnifier, on a cream tile
// following the macOS icon template (824pt rounded tile centered with a drop shadow).
//
// Usage: swift scripts/render-icon.swift <output.png>   (or: make icon)

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func gradient(_ colors: [UInt32], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors.map { rgb($0) } as CFArray, locations: locations)!
}

func roundedBar(_ ctx: CGContext, _ rect: CGRect, _ color: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("context") }

// CoreGraphics origin is bottom-left.

// MARK: Tile

let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0xE6DFD2))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([0xFBF8F2, 0xE6DFD2]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let highlight = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.12), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 720), options: [])
ctx.restoreGState()

ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0x000000, 0.10))
ctx.setLineWidth(4)
ctx.strokePath()

// MARK: Ledger sheet

let card = CGRect(x: 214, y: 250, width: 596, height: 560)
let cardPath = CGPath(roundedRect: card, cornerWidth: 44, cornerHeight: 44, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.18))
ctx.addPath(cardPath)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Dark header band with a title bar.
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
ctx.setFillColor(rgb(0x252A33))
ctx.fill(CGRect(x: card.minX, y: card.maxY - 110, width: card.width, height: 110))
ctx.restoreGState()
roundedBar(ctx, CGRect(x: card.minX + 48, y: card.maxY - 70, width: 170, height: 30), rgb(0xFFFFFF, 0.85))

// Rows: alternating debit (orange) and credit (teal) markers with amount bars.
let rowsY: [CGFloat] = [620, 520, 420, 320]
let markers: [UInt32] = [0xFF8A3D, 0x2DD4BF, 0xFF8A3D, 0x2DD4BF]
let widths: [CGFloat] = [250, 190, 280, 150]
for (i, y) in rowsY.enumerated() {
    if i > 0 {
        ctx.setFillColor(rgb(0x000000, 0.06))
        ctx.fill(CGRect(x: card.minX + 40, y: y + 48, width: card.width - 80, height: 4))
    }
    ctx.setFillColor(rgb(markers[i]))
    ctx.fillEllipse(in: CGRect(x: card.minX + 52, y: y - 22, width: 44, height: 44))
    roundedBar(ctx, CGRect(x: card.minX + 124, y: y - 17, width: widths[i], height: 34), rgb(0x3A404B, 0.75))
}

// MARK: Magnifier

let lensCenter = CGPoint(x: 700, y: 360)
let lensRadius: CGFloat = 118
let ringWidth: CGFloat = 34
let handleEnd = CGPoint(x: 850, y: 208)
let handleWidth: CGFloat = 54

// Handle: flat start on the ring's centerline (hidden by the ring), rounded tip.
// Shaft and tip are filled separately inside one layer so they union and share a shadow.
let dx = handleEnd.x - lensCenter.x, dy = handleEnd.y - lensCenter.y
let length = sqrt(dx * dx + dy * dy)
let handleStart = CGPoint(x: lensCenter.x + dx / length * lensRadius, y: lensCenter.y + dy / length * lensRadius)
let shaft = CGMutablePath()
shaft.move(to: handleStart)
shaft.addLine(to: handleEnd)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.4))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.setFillColor(rgb(0xEE9A1F))
ctx.addPath(shaft.copy(strokingWithWidth: handleWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10))
ctx.fillPath()
ctx.fillEllipse(in: CGRect(x: handleEnd.x - handleWidth / 2, y: handleEnd.y - handleWidth / 2, width: handleWidth, height: handleWidth))
ctx.endTransparencyLayer()
ctx.restoreGState()

// Ring: amber gradient stroke.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x000000, 0.35))
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
ctx.setLineWidth(ringWidth)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    gradient([0xFFC45C, 0xF5A524, 0xC9761A], [0, 0.5, 1]),
    start: CGPoint(x: lensCenter.x - lensRadius, y: lensCenter.y + lensRadius),
    end: CGPoint(x: lensCenter.x + lensRadius, y: lensCenter.y - lensRadius), options: [])
ctx.restoreGState()

guard let image = ctx.makeImage() else { fatalError("image") }
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
