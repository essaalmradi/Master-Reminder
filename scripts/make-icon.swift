import AppKit
import Foundation

// System vector symbol rendered into the macOS icon sizes; no external image dependency.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let bounds = NSRect(x: Double(size) * 0.06, y: Double(size) * 0.06, width: Double(size) * 0.88, height: Double(size) * 0.88)
        NSColor(calibratedRed: 0.06, green: 0.25, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Double(size) * 0.2, yRadius: Double(size) * 0.2).fill()
        let config = NSImage.SymbolConfiguration(pointSize: Double(size) * 0.49, weight: .light)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        let symbol = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
        let symbolRect = NSRect(x: Double(size) * 0.26, y: Double(size) * 0.25, width: Double(size) * 0.49, height: Double(size) * 0.52)
        symbol.draw(in: symbolRect)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
