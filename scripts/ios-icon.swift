import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Headless asset resizing via CoreGraphics (no AppKit drawing context required).
let folder = URL(fileURLWithPath: "iOS/App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let source = URL(fileURLWithPath: "Sources/ReminderCore/Resources/AppIcon.png")
guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(input, 0, nil),
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("Cannot load supplied icon") }
context.setFillColor(CGColor(red: 1.0/255, green: 14.0/255, blue: 22.0/255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
context.draw(original, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let image = context.makeImage(), let output = CGImageDestinationCreateWithURL(folder.appendingPathComponent("AppIcon.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot write icon") }
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Cannot finalize icon") }
let json = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
