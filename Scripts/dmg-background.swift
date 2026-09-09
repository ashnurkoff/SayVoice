#!/usr/bin/env swift
// Draws the disk-image background with CoreGraphics.
//
//   swift Scripts/dmg-background.swift Scripts/dmg/background.png
//
// 660 x 400 pt at 2x (1320 x 800 px, 144 dpi so Finder lays it out in points).
// Left half: the brand gradient panel (accent -> accent2) with the white
// "SayVoice" wordmark (no glyph — the app icon already carries the waveform). Right half: the dark ground with
// a curved arrow running from the left icon slot to the right one and the
// caption. Icon slots sit at (165, 185) and (495, 185) in window points, which
// is what Scripts/make-dmg tells Finder.
//
// Colours are the dark-theme values of the design-system tokens in
// SayVoice/DesignSystem/Tokens/Colors.swift; the text is Onest, registered from
// SayVoice/Resources/Fonts at run time, with the system font as a fallback.
// The output is byte-for-byte reproducible: nothing here depends on the clock,
// the display or the locale.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

let canvasWidth: CGFloat = 660
let canvasHeight: CGFloat = 400
let scale: CGFloat = 2

/// Window points (top-left origin, the coordinate space Finder positions icons
/// in) to CoreGraphics points (bottom-left origin).
func flip(_ y: CGFloat) -> CGFloat { canvasHeight - y }

let leftSlot = CGPoint(x: 165, y: 185)
let rightSlot = CGPoint(x: 495, y: 185)
let panelWidth = leftSlot.x * 2  // 330: the split falls between the two slots

// MARK: - Tokens (DS.Colors, dark appearance)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func token(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

let accent = token(0x7B7FF2)
let accent2 = token(0xA78BFA)
let ground = token(0x17171D)
let mutedColor = token(0x9E9FB0)
let textColor = token(0xF1F1F6)
let onAccent = token(0xFFFFFF)

// MARK: - Fonts

/// Registers Onest from the repository and hands back its family name. The
/// shipped file is a variable font (`Onest[wght].ttf`), so a weight is a
/// variation of the one family rather than a separate face.
func registerOnest() -> String? {
    let scriptDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent()
    let candidates = [
        scriptDirectory.appendingPathComponent("../SayVoice/Resources/Fonts").standardized,
        URL(fileURLWithPath: "SayVoice/Resources/Fonts"),
    ]
    for directory in candidates {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.lastPathComponent.hasPrefix("Onest") && file.pathExtension == "ttf" {
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) else {
                FileHandle.standardError.write(
                    Data("warning: could not register \(file.lastPathComponent)\n".utf8)
                )
                continue
            }
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL)
                as? [CTFontDescriptor]
            if let first = descriptors?.first,
               let family = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute)
                   as? String {
                return family
            }
        }
    }
    return nil
}

let onestFamily = registerOnest()
/// The `wght` OpenType variation axis.
let weightAxis = 0x7767_6874 as CFNumber

/// Onest at a variable weight, or the system font at the nearest weight.
func brandFont(size: CGFloat, weight: CGFloat) -> CTFont {
    if let family = onestFamily {
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: weight as CFNumber] as CFDictionary,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
    let systemWeight: NSFont.Weight = weight >= 600 ? .semibold : .regular
    return NSFont.systemFont(ofSize: size, weight: systemWeight) as CTFont
}

// MARK: - Canvas

guard let context = CGContext(
    data: nil,
    width: Int(canvasWidth * scale),
    height: Int(canvasHeight * scale),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("error: could not create the bitmap context\n".utf8))
    exit(1)
}
context.scaleBy(x: scale, y: scale)
context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// The brand gradient fills the whole canvas.

if let gradient = CGGradient(
    colorsSpace: sRGB, colors: [accent, accent2] as CFArray, locations: [0, 1]
) {
    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvasHeight),
        end: CGPoint(x: canvasWidth, y: 0),
        options: []
    )
    context.restoreGState()
}

// MARK: - Waveform glyph

/// The SF Symbol rendered white, with its own alpha preserved.
func whiteSymbol(_ name: String, pointSize: CGFloat) -> (image: CGImage, size: CGSize)? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return nil }
    let size = symbol.size
    guard size.width > 0, size.height > 0 else { return nil }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((size.width * scale).rounded()),
        pixelsHigh: Int((size.height * scale).rounded()),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = size
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let bounds = NSRect(origin: .zero, size: size)
    symbol.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.setFill()
    bounds.fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    guard let image = rep.cgImage else { return nil }
    return (image, size)
}

/// Seven rounded bars in the shape of the symbol, for the case where SF Symbols
/// are unavailable (a stripped-down or headless toolchain).
func drawFallbackWaveform(centeredAt centre: CGPoint, width: CGFloat) {
    let heights: [CGFloat] = [0.30, 0.62, 0.92, 1.0, 0.92, 0.62, 0.30]
    let bar = width / CGFloat(heights.count * 2 - 1)
    let maxHeight = width * 0.72
    context.setFillColor(onAccent)
    for (index, fraction) in heights.enumerated() {
        let height = maxHeight * fraction
        let x = centre.x - width / 2 + CGFloat(index) * bar * 2
        let rect = CGRect(x: x, y: centre.y - height / 2, width: bar, height: height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: bar / 2, cornerHeight: bar / 2, transform: nil))
    }
    context.fillPath()
}

// The panel carries no glyph: the app icon in the slot already shows the waveform.

// MARK: - Text

context.textMatrix = .identity

/// Draws one line horizontally centred on `x`, sitting on the baseline `y`
/// (both in window points).
func drawCentred(_ string: NSAttributedString, x: CGFloat, baseline y: CGFloat) {
    let line = CTLineCreateWithAttributedString(string)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: x - CGFloat(width) / 2, y: flip(y))
    CTLineDraw(line, context)
}

func run(_ text: String, _ font: CTFont, _ colour: CGColor, tracking: CGFloat = 0)
    -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: colour) ?? .white,
        .kern: tracking,
    ])
}

drawCentred(
    run("SayVoice", brandFont(size: 32, weight: 600), onAccent, tracking: -0.3),
    x: canvasWidth / 2,
    baseline: 64
)

let caption = NSMutableAttributedString()
let captionFont = brandFont(size: 15, weight: 400)
caption.append(run("Drag ", captionFont, onAccent.copy(alpha: 0.72) ?? onAccent, tracking: 0.2))
caption.append(run("SayVoice", captionFont, onAccent, tracking: 0.2))
caption.append(run(" to Applications", captionFont, onAccent.copy(alpha: 0.72) ?? onAccent, tracking: 0.2))
drawCentred(caption, x: canvasWidth / 2, baseline: 338)

// MARK: - Arrow

// It runs between the two icon slots and sits below their vertical centre, so a
// 128 pt icon at either end never covers it. Window points, converted on the way in.
let arrowStart = CGPoint(x: 240, y: flip(214))
let arrowEnd = CGPoint(x: 420, y: flip(214))
let control1 = CGPoint(x: 300, y: flip(232))
let control2 = CGPoint(x: 360, y: flip(232))

context.saveGState()
context.setStrokeColor(onAccent.copy(alpha: 0.7) ?? onAccent)
context.setLineWidth(4.5)
context.setLineCap(.round)
context.setLineJoin(.round)

context.move(to: arrowStart)
context.addCurve(to: arrowEnd, control1: control1, control2: control2)

// The head follows the curve's tangent at the end point, and is one polyline so
// its apex gets a round join rather than two overlapping caps.
let tangent = CGPoint(x: arrowEnd.x - control2.x, y: arrowEnd.y - control2.y)
let length = (tangent.x * tangent.x + tangent.y * tangent.y).squareRoot()
let direction = CGPoint(x: tangent.x / length, y: tangent.y / length)
let headLength: CGFloat = 15
let headAngle: CGFloat = 0.42  // ~24 degrees off the tangent

func barb(_ sign: CGFloat) -> CGPoint {
    let angle = sign * headAngle
    let dx = direction.x * cos(angle) - direction.y * sin(angle)
    let dy = direction.x * sin(angle) + direction.y * cos(angle)
    return CGPoint(x: arrowEnd.x - dx * headLength, y: arrowEnd.y - dy * headLength)
}

context.move(to: barb(1))
context.addLine(to: arrowEnd)
context.addLine(to: barb(-1))
context.strokePath()
context.restoreGState()

// MARK: - Output

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Scripts/dmg/background.png"
let outputURL = URL(fileURLWithPath: outputPath)

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("error: could not snapshot the context\n".utf8))
    exit(1)
}
try? FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    FileHandle.standardError.write(Data("error: could not open \(outputPath) for writing\n".utf8))
    exit(1)
}
// 144 dpi so Finder measures the image as 660 x 400 points, not pixels.
CGImageDestinationAddImage(destination, image, [
    kCGImagePropertyDPIWidth: 144,
    kCGImagePropertyDPIHeight: 144,
] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: could not write \(outputPath)\n".utf8))
    exit(1)
}
print(outputPath)
