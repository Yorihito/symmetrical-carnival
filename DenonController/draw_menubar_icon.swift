import Cocoa
import Foundation

// Draw at large size first, then downsample for crispness
func createMenuBarIcon(outputSize: CGFloat, filename: String) {
    let drawSize: CGFloat = 256  // draw at 256, downsample later
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    guard let context = CGContext(data: nil,
                                  width: Int(drawSize),
                                  height: Int(drawSize),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    
    context.clear(CGRect(x: 0, y: 0, width: drawSize, height: drawSize))
    
    let cx = drawSize / 2   // 128
    let cy = drawSize / 2   // 128
    let radius: CGFloat = 96
    
    // Ring
    context.setStrokeColor(NSColor.black.cgColor)
    context.setLineWidth(18)
    context.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    
    // Dot at exactly 12 o'clock = (cx, cy + dist)  [Y goes UP in CGContext]
    let dotRadius: CGFloat = 14
    let dotDist: CGFloat = radius * 0.68
    let dotX = cx         // exactly center horizontally
    let dotY = cy + dotDist  // exactly top
    
    context.setFillColor(NSColor.black.cgColor)
    context.fillEllipse(in: CGRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    
    guard let cgImage = context.makeImage() else { return }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: drawSize, height: drawSize))
    
    // Downsample to target size
    let resultImage = NSImage(size: NSSize(width: outputSize, height: outputSize))
    resultImage.lockFocus()
    nsImage.draw(in: NSRect(x: 0, y: 0, width: outputSize, height: outputSize))
    resultImage.unlockFocus()
    
    let pngData = NSBitmapImageRep(data: resultImage.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try? pngData.write(to: URL(fileURLWithPath: filename))
    print("Generated \(filename) at \(outputSize)x\(outputSize)")
}

createMenuBarIcon(outputSize: 16, filename: "MenuBarIcon.png")
createMenuBarIcon(outputSize: 32, filename: "MenuBarIcon@2x.png")
