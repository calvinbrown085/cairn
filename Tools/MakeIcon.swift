import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Renders the Cairn app icon: cream sheets stacked on warm terracotta.
/// Run with: swift Tools/MakeIcon.swift <output.png>

let size = 1024.0
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Warm terracotta ground, lit from the top-left.
let gradient = CGGradient(
    colorsSpace: space,
    colors: [rgb(0xC26A42), rgb(0x8E3A22)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

/// One sheet of paper: a rounded rect with a soft drop shadow.
func sheet(y: CGFloat, inset: CGFloat, height: CGFloat, fill: UInt32, shadow: Bool) {
    let rect = CGRect(x: inset, y: y, width: size - inset * 2, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)

    ctx.saveGState()
    if shadow {
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x3A1408, 0.34))
    }
    ctx.setFillColor(rgb(fill))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

// Three sheets, drawn back to front. The two behind peek out above the top
// one and step inward, so the group reads as a stack seen slightly from below
// rather than as three stacked bars.
sheet(y: 726, inset: 286, height: 48, fill: 0xDCC5AB, shadow: true)
sheet(y: 670, inset: 240, height: 58, fill: 0xEBDAC4, shadow: true)
sheet(y: 250, inset: 196, height: 420, fill: 0xFDF8F0, shadow: true)

// Ruled lines on the front sheet, so it reads as a page of prose.
let lineInset = 196.0 + 52
let lineWidth = size - lineInset * 2

// The headline rule, in the app's terracotta.
ctx.setFillColor(rgb(0xA0472B, 0.92))
ctx.addPath(CGPath(
    roundedRect: CGRect(x: lineInset, y: 566, width: lineWidth * 0.58, height: 28),
    cornerWidth: 14, cornerHeight: 14, transform: nil
))
ctx.fillPath()

// Body lines, the last one short the way a paragraph ends.
ctx.setFillColor(rgb(0xC08050, 0.5))
for (index, ratio) in [1.0, 1.0, 1.0, 0.72].enumerated() {
    let rect = CGRect(
        x: lineInset,
        y: 486 - Double(index) * 62,
        width: lineWidth * ratio,
        height: 22
    )
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
}

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: output)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output)")
