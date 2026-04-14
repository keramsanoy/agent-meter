import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else { exit(2) }
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
guard let source = NSImage(contentsOf: sourceURL) else { exit(1) }
let icons: [(String, CGFloat, CGFloat)] = [("icon_16x16.png",16,1),("icon_16x16@2x.png",16,2),("icon_32x32.png",32,1),("icon_32x32@2x.png",32,2),("icon_128x128.png",128,1),("icon_128x128@2x.png",128,2),("icon_256x256.png",256,1),("icon_256x256@2x.png",256,2),("icon_512x512.png",512,1),("icon_512x512@2x.png",512,2)]
for (name, size, scale) in icons {
    let pixelSize = NSSize(width: size * scale, height: size * scale)
    let image = NSImage(size: pixelSize)
    image.lockFocus()
    let sourceSize = source.size
    let square = min(sourceSize.width, sourceSize.height)
    let sourceRect = NSRect(x: (sourceSize.width-square)/2, y: (sourceSize.height-square)/2, width: square, height: square)
    source.draw(in: NSRect(origin: .zero, size: pixelSize), from: sourceRect, operation: .sourceOver, fraction: 1)
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try png.write(to: outputDirectory.appendingPathComponent(name))
}
