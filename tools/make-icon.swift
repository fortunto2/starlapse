#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Generates the app icon. Kept as source rather than a checked-in binary so the design can
// be reasoned about and changed — an icon is code like anything else.
//
// The mark is the app in one image: a star trail. A point of light, and the arc it drew
// while the shutter was open. That is literally what the app produces, and it reads at
// 40 points as well as at 1024.

let size = 1024.0
let scale = size / 1024.0

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create context")
}

// MARK: - Night

// Not pure black: a real night sky has a faint gradient, and a flat black icon disappears
// against a dark home screen.
let background = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.05, green: 0.06, blue: 0.11, alpha: 1),
        CGColor(srgbRed: 0.01, green: 0.01, blue: 0.03, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// MARK: - The trail

let centre = CGPoint(x: size * 0.5, y: size * 0.5)
let radius = size * 0.29
let lineWidth = size * 0.075

// The arc fades out behind the star, the way a trail dims toward where the exposure began.
// Drawn as short segments with falling alpha — a stroked gradient needs a mask, and this is
// two lines instead of twenty.
// Nearly a full turn, centred. A short arc left one side of the icon empty; the sky turns
// in circles, so the mark should too.
let startAngle = 0.62 * Double.pi
let endAngle = 2.42 * Double.pi
let segments = 320

context.setLineCap(.round)
for index in 0..<segments {
    let t0 = Double(index) / Double(segments)
    let t1 = Double(index + 1) / Double(segments)
    let a0 = startAngle + (endAngle - startAngle) * t0
    let a1 = startAngle + (endAngle - startAngle) * t1

    // Ease in: nearly invisible at the tail, full brightness at the head.
    let alpha = pow(t0, 1.7)

    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
    context.setLineWidth(lineWidth * (0.55 + 0.45 * t0))
    context.addArc(
        center: centre, radius: radius,
        startAngle: a0, endAngle: a1, clockwise: false
    )
    context.strokePath()
}

// MARK: - The star

let head = CGPoint(
    x: centre.x + radius * cos(endAngle),
    y: centre.y + radius * sin(endAngle)
)

// Glow, then core. A bright star on a long exposure blooms; without the halo the head of
// the trail looks like a cut end rather than a light.
let glow = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85),
        CGColor(srgbRed: 0.75, green: 0.85, blue: 1, alpha: 0.28),
        CGColor(srgbRed: 0.6, green: 0.75, blue: 1, alpha: 0),
    ] as CFArray,
    locations: [0, 0.35, 1]
)!
context.drawRadialGradient(
    glow,
    startCenter: head, startRadius: 0,
    endCenter: head, endRadius: size * 0.15,
    options: []
)

context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(
    x: head.x - lineWidth * 0.78,
    y: head.y - lineWidth * 0.78,
    width: lineWidth * 1.56,
    height: lineWidth * 1.56
))

// MARK: - Write

guard let image = context.makeImage() else { fatalError("No image") }

let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "AppIcon.png")

let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("No PNG data")
}
try data.write(to: output)
print("Wrote \(Int(size))×\(Int(size)) icon to \(output.path) (scale \(scale))")
