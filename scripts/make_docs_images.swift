#!/usr/bin/env swift
// Renders documentation images: the limits panel (with live-looking rows) and
// a DMG install illustration. Pure CoreGraphics, headless-safe.
// Usage: swift scripts/make_docs_images.swift <outdir>

import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let outdir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let scale: CGFloat = 2 // retina crispness
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func cgcolor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

func makeContext(_ w: CGFloat, _ h: CGFloat) -> CGContext {
    CGContext(
        data: nil, width: Int(w * scale), height: Int(h * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func writePNG(_ ctx: CGContext, _ name: String) {
    let url = URL(fileURLWithPath: outdir).appendingPathComponent(name)
    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("destination \(name)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("finalize \(name)") }
    print("wrote \(url.path)")
}

func capsule(_ ctx: CGContext, _ rect: CGRect, _ color: CGColor) {
    let cap = rect.height / 2
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cap, cornerHeight: cap, transform: nil))
    ctx.fillPath()
}

func drawText(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
              weight: NSFont.Weight, color: CGColor, mono: Bool = false, alignRight: CGFloat? = nil) {
    let font = mono
        ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color)!,
    ]
    let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    let str = text as NSString
    var pt = CGPoint(x: x, y: y)
    if let right = alignRight {
        let w = str.size(withAttributes: attributes).width
        pt.x = right - w
    }
    str.draw(at: pt, withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func rounded(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
    ctx.setFillColor(fill)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

// MARK: - Panel image (EN labels; live percentages)

let pw: CGFloat = 420, ph: CGFloat = 372
let p = makeContext(pw, ph)
p.scaleBy(x: scale, y: scale)

rounded(p, CGRect(x: 0.5, y: 0.5, width: pw - 1, height: ph - 1), radius: 14, fill: cgcolor(0.11, 0.11, 0.12))
p.setStrokeColor(cgcolor(1, 1, 1, 0.10))
p.setLineWidth(1)
p.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: pw - 1, height: ph - 1), cornerWidth: 14, cornerHeight: 14, transform: nil))
p.strokePath()

// Tabs
capsule(p, CGRect(x: 18, y: ph - 44, width: 96, height: 30), cgcolor(0.20, 0.45, 1.0))
drawText(p, "Claude", x: 40, y: ph - 34, size: 15, weight: .semibold, color: cgcolor(1, 1, 1))
capsule(p, CGRect(x: 122, y: ph - 44, width: 82, height: 30), cgcolor(1, 1, 1, 0.10))
drawText(p, "Codex", x: 140, y: ph - 34, size: 15, weight: .medium, color: cgcolor(1, 1, 1))

struct Row { let title: String; let pct: CGFloat; let reset: String }
let rows: [Row] = [
    Row(title: "5-hour", pct: 0, reset: "resets in 2h 24m"),
    Row(title: "Weekly", pct: 8, reset: "resets in 153h 4m"),
    Row(title: "Weekly · Fable", pct: 16, reset: "resets in 153h 4m"),
]

var yTop = ph - 84
for row in rows {
    drawText(p, row.title, x: 22, y: yTop, size: 17, weight: .semibold, color: cgcolor(1, 1, 1))
    drawText(p, "\(Int(row.pct))%", x: 0, y: yTop, size: 17, weight: .bold,
             color: cgcolor(1, 1, 1), alignRight: pw - 22)
    let barY = yTop - 26
    capsule(p, CGRect(x: 20, y: barY, width: pw - 42, height: 12), cgcolor(1, 1, 1, 0.12))
    if row.pct > 0 {
        capsule(p, CGRect(x: 20, y: barY, width: max(12, (pw - 42) * row.pct / 100), height: 12), cgcolor(0.24, 0.80, 0.36))
    }
    drawText(p, row.reset, x: 22, y: barY - 22, size: 13, weight: .medium, color: cgcolor(1, 1, 1, 0.55))
    yTop -= 78
}

drawText(p, "updated 1m ago", x: 22, y: 18, size: 13, weight: .medium, color: cgcolor(1, 1, 1, 0.55))
drawText(p, "⚙", x: pw - 74, y: 18, size: 14, weight: .regular, color: cgcolor(1, 1, 1, 0.65))
drawText(p, "⟳", x: pw - 46, y: 18, size: 14, weight: .regular, color: cgcolor(1, 1, 1, 0.65))
writePNG(p, "panel.png")

// MARK: - Install illustration (DMG layout)

let iw: CGFloat = 560, ih: CGFloat = 340
let c = makeContext(iw, ih)
c.scaleBy(x: scale, y: scale)

rounded(c, CGRect(x: 0.5, y: 0.5, width: iw - 1, height: ih - 1), radius: 12, fill: cgcolor(0.145, 0.145, 0.155))
c.setStrokeColor(cgcolor(1, 1, 1, 0.08))
c.setLineWidth(1)
c.addPath(CGPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: iw - 1, height: ih - 1), cornerWidth: 12, cornerHeight: 12, transform: nil))
c.strokePath()

// Titlebar dots
for (i, colr) in [(0.98, 0.38, 0.36), (0.98, 0.75, 0.20), (0.28, 0.78, 0.32)].enumerated() {
    c.setFillColor(cgcolor(colr.0, colr.1, colr.2))
    c.fillEllipse(in: CGRect(x: 18 + CGFloat(i) * 22, y: ih - 26, width: 12, height: 12))
}

// App tile
let appX: CGFloat = 110, tileY: CGFloat = 120, tileSize: CGFloat = 128
rounded(c, CGRect(x: appX, y: tileY, width: tileSize, height: tileSize), radius: 29, fill: cgcolor(0.12, 0.12, 0.13))
let barH: CGFloat = 11, gap: CGFloat = 9, side: CGFloat = 21
let trackW = tileSize - side * 2
var by = tileY + tileSize / 2 + (barH * 3 + gap * 2) / 2 - barH
for f in [CGFloat(0.42), 0.68, 0.94] {
    capsule(c, CGRect(x: appX + side, y: by, width: trackW, height: barH), cgcolor(1, 1, 1, 0.10))
    capsule(c, CGRect(x: appX + side, y: by, width: max(barH, trackW * f), height: barH), cgcolor(0.27, 0.83, 0.38))
    by -= barH + gap
}
drawText(c, "limit-bar.app", x: appX - 20, y: tileY - 30, size: 14, weight: .medium, color: cgcolor(1, 1, 1, 0.85), alignRight: appX + tileSize + 20)

// Drag arrow
c.setStrokeColor(cgcolor(1, 1, 1, 0.55))
c.setLineWidth(3)
c.move(to: CGPoint(x: appX + tileSize + 34, y: tileY + tileSize / 2 + 14))
c.addLine(to: CGPoint(x: iw - 150, y: tileY + tileSize / 2 + 14))
c.strokePath()
// arrowhead
c.setFillColor(cgcolor(1, 1, 1, 0.55))
let tipX = iw - 148, tipY = tileY + tileSize / 2 + 14
let tri = CGMutablePath()
tri.move(to: CGPoint(x: tipX + 12, y: tipY))
tri.addLine(to: CGPoint(x: tipX - 6, y: tipY + 8))
tri.addLine(to: CGPoint(x: tipX - 6, y: tipY - 8))
tri.closeSubpath()
c.addPath(tri)
c.fillPath()

// Applications folder glyph (simple blue folder)
let fx = iw - 132
rounded(c, CGRect(x: fx, y: tileY - 4, width: 118, height: 86), radius: 10, fill: cgcolor(0.18, 0.42, 0.95))
rounded(c, CGRect(x: fx, y: tileY + 62, width: 52, height: 24), radius: 7, fill: cgcolor(0.22, 0.50, 1.0))
drawText(c, "Applications", x: fx - 14, y: tileY - 30, size: 14, weight: .medium, color: cgcolor(1, 1, 1, 0.85), alignRight: fx + 132)

drawText(c, "Drag limit-bar into Applications to install", x: 0, y: 26, size: 14, weight: .medium,
         color: cgcolor(1, 1, 1, 0.60), alignRight: iw / 2 + 130)
writePNG(c, "install.png")
