#!/usr/bin/env swift
// Renders the limit-bar app icon: three green progress bars on a dark squircle.
// Usage: swift scripts/make_icon.swift <output-png> [size]
// Pure CoreGraphics + ImageIO so it runs headless (no WindowServer needed).

import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1024) : 1024
let s = size

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func cgcolor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}

// macOS grid keeps the squircle at ~82% of the canvas.
let inset = s * 0.09
let box = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
let radius = box.width * 0.225
let squircle = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Base fill + soft drop shadow for depth on light backgrounds.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.02,
              color: cgcolor(0, 0, 0, 0.35))
ctx.setFillColor(cgcolor(0.12, 0.12, 0.13))
ctx.addPath(squircle)
ctx.fillPath()
ctx.restoreGState()

// Vertical charcoal gradient clipped to the squircle.
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bgGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [cgcolor(0.165, 0.165, 0.175), cgcolor(0.075, 0.075, 0.085)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: box.midX, y: box.maxY),
                       end: CGPoint(x: box.midX, y: box.minY), options: [])

// Three progress bars: faint track + green fill of increasing length.
let barHeight = s * 0.085
let barGap = s * 0.062
let sidePadding = box.width * 0.17
let trackWidth = box.width - sidePadding * 2
let totalBarsHeight = barHeight * 3 + barGap * 2
var y = box.midY + totalBarsHeight / 2 - barHeight

let fills: [CGFloat] = [0.42, 0.68, 0.94]
let cap = barHeight / 2

for fill in fills {
    let trackRect = CGRect(x: box.minX + sidePadding, y: y, width: trackWidth, height: barHeight)
    let trackPath = CGPath(roundedRect: trackRect, cornerWidth: cap, cornerHeight: cap, transform: nil)

    ctx.setFillColor(cgcolor(1, 1, 1, 0.10))
    ctx.addPath(trackPath)
    ctx.fillPath()

    let fillWidth = trackWidth * fill
    if fillWidth > cap {
        let fillRect = CGRect(x: trackRect.minX, y: y, width: fillWidth, height: barHeight)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: min(cap, fillWidth / 2),
                              cornerHeight: min(cap, fillWidth / 2), transform: nil)
        ctx.saveGState()
        ctx.addPath(fillPath)
        ctx.clip()
        let green = CGGradient(
            colorsSpace: colorSpace,
            colors: [cgcolor(0.38, 0.90, 0.44), cgcolor(0.20, 0.74, 0.32)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(green, start: CGPoint(x: 0, y: y + barHeight),
                               end: CGPoint(x: 0, y: y), options: [])
        ctx.restoreGState()
    }

    y -= barHeight + barGap
}

// Glassy hairline highlight along the top edge of the squircle.
ctx.setStrokeColor(cgcolor(1, 1, 1, 0.07))
ctx.setLineWidth(max(1, s * 0.0035))
ctx.addPath(squircle)
ctx.strokePath()

ctx.restoreGState()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: output) as CFURL,
          UTType.png.identifier as CFString, 1, nil
      ) else {
    fatalError("could not create image destination")
}
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else {
    fatalError("could not write png")
}
print("wrote \(output) (\(Int(s))x\(Int(s)))")
