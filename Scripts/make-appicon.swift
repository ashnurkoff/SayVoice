// Renders Scripts/icon/sayvoice-icon.svg into the app icon set at every macOS size.
// The squircle artwork is drawn into the standard 824/1024 icon grid so it sits
// at the same size as other Dock icons, with transparent margins around it.
// Usage: swift Scripts/make-appicon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let svgURL = root.appendingPathComponent("Scripts/icon/sayvoice-icon.svg")
let setURL = root.appendingPathComponent("SayVoice/Resources/Assets.xcassets/AppIcon.appiconset")
guard let svg = NSImage(contentsOf: svgURL) else { fatalError("cannot read \(svgURL.path)") }

let grid: CGFloat = 824.0 / 1024.0
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let side = CGFloat(px) * grid
    let inset = (CGFloat(px) - side) / 2
    svg.draw(in: NSRect(x: inset, y: inset, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: setURL.appendingPathComponent("icon_\(px).png"))
    print("icon_\(px).png")
}
