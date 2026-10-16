#!/usr/bin/env swift
// Renders the 1024×1024 app icon master to Resources/Brand/AppIcon.png.
//
// Usage:
//   swift scripts/render-app-icon.swift [--variant earbud|earbud-silver|earbud-blue] [output.png]
//   swift scripts/render-app-icon.swift --sheet preview.png   # all variants + small sizes
//
// Geometry follows the macOS icon grid: an 824×824 tile centered on a
// 1024×1024 canvas, leaving room for the system drop shadow.

import AppKit

let canvas: CGFloat = 1024
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let defaultOutput = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Brand/AppIcon.png").path

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: locations
    )!
}

/// Approximates Apple's continuous-corner tile with a superellipse-style path.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let r = min(radius, rect.width / 2, rect.height / 2)
    let e = r * 1.12
    let k: CGFloat = 0.6
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)

    path.move(to: CGPoint(x: minX + e, y: minY))
    path.addLine(to: CGPoint(x: maxX - e, y: minY))
    path.addCurve(
        to: CGPoint(x: maxX, y: minY + e),
        control1: CGPoint(x: maxX - e + e * k, y: minY),
        control2: CGPoint(x: maxX, y: minY + e - e * k)
    )
    path.addLine(to: CGPoint(x: maxX, y: maxY - e))
    path.addCurve(
        to: CGPoint(x: maxX - e, y: maxY),
        control1: CGPoint(x: maxX, y: maxY - e + e * k),
        control2: CGPoint(x: maxX - e + e * k, y: maxY)
    )
    path.addLine(to: CGPoint(x: minX + e, y: maxY))
    path.addCurve(
        to: CGPoint(x: minX, y: maxY - e),
        control1: CGPoint(x: minX + e - e * k, y: maxY),
        control2: CGPoint(x: minX, y: maxY - e + e * k)
    )
    path.addLine(to: CGPoint(x: minX, y: minY + e))
    path.addCurve(
        to: CGPoint(x: minX + e, y: minY),
        control1: CGPoint(x: minX, y: minY + e - e * k),
        control2: CGPoint(x: minX + e - e * k, y: minY)
    )
    path.closeSubpath()
    return path
}

func makeContext(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    return ctx
}

// MARK: Shared tile

/// Fills the tile (with the system-style drop shadow), then clips to it so the
/// variant can paint its artwork inside. Coordinates are top-left origin.
func paintTile(_ ctx: CGContext, top: UInt32, bottom: UInt32, art: (CGContext) -> Void) {
    let tile = continuousRect(tileRect, radius: 185)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.30))
    ctx.addPath(tile)
    ctx.setFillColor(color(bottom))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([color(top), color(bottom)], [0, 1]),
        start: CGPoint(x: 0, y: tileRect.minY),
        end: CGPoint(x: 0, y: tileRect.maxY),
        options: []
    )
    art(ctx)
    ctx.restoreGState()

    // Hairline rim so the tile edge holds up on both light and dark wallpapers.
    ctx.saveGState()
    ctx.addPath(continuousRect(tileRect.insetBy(dx: 1.5, dy: 1.5), radius: 184))
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ c: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(c)
    ctx.fillPath()
}

func capsule(_ rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: Artwork

/// A single earbud with tap marks radiating off its stem: the headset button,
/// pressed. The default palette is a white tile with systemBlue marks.
struct EarbudPalette {
    var tileTop: UInt32, tileBottom: UInt32
    var shadow: CGColor, budEdge: UInt32, marks: UInt32
    var budRim: UInt32? = nil
}

func drawEarbud(_ ctx: CGContext, _ p: EarbudPalette) {
    paintTile(ctx, top: p.tileTop, bottom: p.tileBottom) { ctx in
        // Lean the earbud to the right (clockwise; y grows downward).
        let tilt = CGFloat.pi / 14
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 512)
        ctx.rotate(by: tilt)
        ctx.translateBy(x: -512, y: -512)
        let bud = CGPath(ellipseIn: CGRect(x: 268, y: 196, width: 340, height: 300), transform: nil)
            .union(capsule(CGRect(x: 478, y: 330, width: 124, height: 520)))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: p.shadow)
        fill(ctx, bud, color(0xFFFFFF))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(bud)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([color(0xFFFFFF), color(p.budEdge)], [0, 1]),
            start: CGPoint(x: 300, y: 0), end: CGPoint(x: 620, y: 0), options: []
        )
        ctx.restoreGState()
        if let rim = p.budRim {
            ctx.addPath(bud)
            ctx.setStrokeColor(color(rim))
            ctx.setLineWidth(6)
            ctx.strokePath()
        }
        // Speaker grille
        fill(ctx, capsule(CGRect(x: 330, y: 300, width: 120, height: 64)), color(0x1C1C1E, 0.85))
        // Tap marks radiating from the stem, fanned around the horizontal
        // regardless of the earbud's tilt.
        let c = CGPoint(x: 566, y: 700)
        for angle in [-CGFloat.pi / 5, 0, CGFloat.pi / 5].map({ $0 - tilt }) {
            let line = CGMutablePath()
            line.move(to: CGPoint(x: c.x + cos(angle) * 152, y: c.y + sin(angle) * 152))
            line.addLine(to: CGPoint(x: c.x + cos(angle) * 244, y: c.y + sin(angle) * 244))
            fill(ctx, line.copy(strokingWithWidth: 46, lineCap: .round, lineJoin: .round, miterLimit: 10), color(p.marks))
        }
        ctx.restoreGState()
    }
}

let variants: [(String, String, (CGContext) -> Void)] = [
    ("earbud", "Earbud · White", { drawEarbud($0, EarbudPalette(
        tileTop: 0xFFFFFF, tileBottom: 0xF0F0F4, shadow: color(0x1C2B4A, 0.40), budEdge: 0xC9CFDA, marks: 0x007AFF, budRim: 0xD3D8E0)) }),
    ("earbud-silver", "Earbud · Silver (alt)", { drawEarbud($0, EarbudPalette(
        tileTop: 0xF7F7FA, tileBottom: 0xDCDDE3, shadow: color(0x1C2B4A, 0.32), budEdge: 0xD9DDE5, marks: 0x007AFF)) }),
    ("earbud-blue", "Earbud · Blue (alt)", { drawEarbud($0, EarbudPalette(
        tileTop: 0x4BA6FF, tileBottom: 0x0059D6, shadow: color(0x002A6B, 0.45), budEdge: 0xE4E8EF, marks: 0xFFFFFF)) }),
]

func renderIcon(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = makeContext(width: Int(canvas), height: Int(canvas))
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

func downscale(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = makeContext(width: size, height: size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Rendered: \(path)")
}

// MARK: Preview sheet

/// One column per variant: large icon, then 64/32/16 px (each shown at true
/// pixels and magnified 4× with nearest-neighbour) on light and dark strips.
func renderSheet(to path: String) throws {
    let colW = 420, height = 760
    let ctx = makeContext(width: colW * variants.count, height: height)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fill(CGRect(x: 0, y: 0, width: colW * variants.count, height: height))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    for (i, variant) in variants.enumerated() {
        let x0 = CGFloat(i * colW)
        let icon = renderIcon(variant.2)
        ctx.draw(icon, in: CGRect(x: x0 + 30, y: CGFloat(height) - 390, width: 360, height: 360))
        (variant.1 as NSString).draw(
            at: NSPoint(x: x0 + 40, y: CGFloat(height) - 420),
            withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold)]
        )
        for (row, bg) in [UInt32(0xECECEC), UInt32(0x1E1E1E)].enumerated() {
            let stripY = CGFloat(height) - 560 - CGFloat(row) * 160
            ctx.setFillColor(color(bg))
            ctx.fill(CGRect(x: x0 + 20, y: stripY, width: CGFloat(colW - 40), height: 140))
            var x = x0 + 34
            for size in [64, 32, 16] {
                let small = downscale(icon, to: size)
                let midY = stripY + 70
                ctx.interpolationQuality = .high
                ctx.draw(small, in: CGRect(x: x, y: midY - CGFloat(size) / 2, width: CGFloat(size), height: CGFloat(size)))
                x += CGFloat(size) + 10
                if size < 64 {
                    ctx.interpolationQuality = .none
                    let mag = CGFloat(size * 4 > 96 ? 96 : size * 4)
                    ctx.draw(small, in: CGRect(x: x, y: midY - mag / 2, width: mag, height: mag))
                    x += mag + 14
                }
            }
        }
    }
    try writePNG(ctx.makeImage()!, to: path)
}

// MARK: Main

var args = Array(CommandLine.arguments.dropFirst())
if let i = args.firstIndex(of: "--sheet") {
    try renderSheet(to: args.count > i + 1 ? args[i + 1] : "icon-sheet.png")
    exit(0)
}
var variantName = "earbud"
if let i = args.firstIndex(of: "--variant"), args.count > i + 1 {
    variantName = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
guard let variant = variants.first(where: { $0.0 == variantName }) else {
    FileHandle.standardError.write("Unknown variant \(variantName)\n".data(using: .utf8)!)
    exit(1)
}
try writePNG(renderIcon(variant.2), to: args.first ?? defaultOutput)
