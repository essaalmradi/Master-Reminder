import AppKit
import Foundation

// Resize the supplied original icon; never redraw or recolor the brand mark.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: "Sources/ReminderCore/Resources/AppIcon.png")
guard let original = NSImage(contentsOf: source) else { fatalError("Missing supplied app icon") }
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: size, height: size)
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        original.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
