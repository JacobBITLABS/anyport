import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Generates the SSHPortBar icons:
//   Assets.xcassets/AppIcon.appiconset/*      – full macOS app icon set
//   Assets.xcassets/StatusBarIcon.imageset/*  – 18pt template glyph for the menu bar
// Usage: swift Scripts/make_icons.swift <project-root>

let projectRoot = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

let fileManager = FileManager.default
let appIconDir = URL(fileURLWithPath: projectRoot)
    .appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let statusIconDir = URL(fileURLWithPath: projectRoot)
    .appendingPathComponent("Assets.xcassets/StatusBarIcon.imageset")
try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: statusIconDir, withIntermediateDirectories: true)

func pngContext(_ size: CGFloat) -> CGContext {
    CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func save(_ context: CGContext, _ name: String, to directory: URL) {
    let url = directory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(url.path)")
}

/// The logo: a terminal prompt chevron ">" whose line feeds into a port slot.
/// Drawn in an 18×18 design grid, scaled by `s`.
func chevronIntoPort(_ context: CGContext, glyphScale s: CGFloat, chevronColor: CGColor, portColor: CGColor) {
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // ">" prompt chevron
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: 3.2 * s, y: 4.8 * s))
    chevron.addLine(to: CGPoint(x: 7.6 * s, y: 9.0 * s))
    chevron.addLine(to: CGPoint(x: 3.2 * s, y: 13.2 * s))
    context.addPath(chevron)
    context.setStrokeColor(chevronColor)
    context.setLineWidth(2.4 * s)
    context.strokePath()

    // line running from the prompt into the port
    context.move(to: CGPoint(x: 9.0 * s, y: 9.0 * s))
    context.addLine(to: CGPoint(x: 12.6 * s, y: 9.0 * s))
    context.setStrokeColor(chevronColor)
    context.setLineWidth(2.2 * s)
    context.strokePath()

    // port slot (drawn last so the connector tucks underneath it)
    let slot = CGRect(x: 11.7 * s, y: 6.5 * s, width: 3.4 * s, height: 5.0 * s)
    context.addPath(
        CGPath(roundedRect: slot, cornerWidth: 1.7 * s, cornerHeight: 1.7 * s, transform: nil)
    )
    context.setStrokeColor(portColor)
    context.setLineWidth(1.8 * s)
    context.strokePath()
}

// MARK: - Status bar glyph (black + alpha; rendered as template by macOS)

let statusRenditions: [(scale: CGFloat, name: String)] = [
    (1, "statusbar.png"),
    (2, "statusbar@2x.png"),
]
for rendition in statusRenditions {
    let context = pngContext(18 * rendition.scale)
    let black = CGColor(gray: 0, alpha: 1)
    chevronIntoPort(context, glyphScale: rendition.scale, chevronColor: black, portColor: black)
    save(context, rendition.name, to: statusIconDir)
}

// MARK: - App icon (macOS squircle, 824/1024 canvas with ~185 corner radius)

func renderAppIcon(_ pixelSize: CGFloat) -> CGContext {
    let context = pngContext(pixelSize)
    let s = pixelSize / 1024

    let inset = 116 * s
    let bounds = CGRect(x: inset, y: inset, width: pixelSize - 2 * inset, height: pixelSize - 2 * inset)
    let cornerRadius = 185.4 * s
    context.addPath(
        CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    )
    context.clip()

    let rgb = CGColorSpaceCreateDeviceRGB()

    // deep navy background, lighter at the top
    let background = CGGradient(
        colorsSpace: rgb,
        colors: [
            CGColor(red: 0.125, green: 0.153, blue: 0.243, alpha: 1),
            CGColor(red: 0.043, green: 0.059, blue: 0.114, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 0, y: pixelSize),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // soft glow behind the glyph
    let glow = CGGradient(
        colorsSpace: rgb,
        colors: [
            CGColor(gray: 1, alpha: 0.10),
            CGColor(gray: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: pixelSize * 0.5, y: pixelSize * 0.80),
        startRadius: 0,
        endCenter: CGPoint(x: pixelSize * 0.5, y: pixelSize * 0.80),
        endRadius: pixelSize * 0.55,
        options: []
    )

    // glyph, centered, ~60% of the canvas
    let glyphScale = pixelSize * 0.60 / 18
    context.saveGState()
    context.translateBy(x: (pixelSize - 18 * glyphScale) / 2, y: (pixelSize - 18 * glyphScale) / 2)
    chevronIntoPort(
        context,
        glyphScale: glyphScale,
        chevronColor: CGColor(gray: 1, alpha: 0.97),
        portColor: CGColor(red: 0.220, green: 0.741, blue: 0.976, alpha: 1)  // cyan port
    )
    context.restoreGState()

    return context
}

// (pixel size, file name) — every macOS app icon slot
let appIconRenditions: [(pixels: CGFloat, name: String)] = [
    (16, "icon_16.png"),
    (32, "icon_16@2x.png"),
    (32, "icon_32.png"),
    (64, "icon_32@2x.png"),
    (128, "icon_128.png"),
    (256, "icon_128@2x.png"),
    (256, "icon_256.png"),
    (512, "icon_256@2x.png"),
    (512, "icon_512.png"),
    (1024, "icon_512@2x.png"),
]
for rendition in appIconRenditions {
    save(renderAppIcon(rendition.pixels), rendition.name, to: appIconDir)
}
