import Cocoa
import Foundation

func processIcon() {
    let inputPath = "/Users/ytada/.gemini/antigravity/brain/190512b6-7f79-4bb4-ba6b-85f9c956aab0/minimal_dial_app_icon_1778029611420.png"
    guard let image = NSImage(contentsOfFile: inputPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return
    }
    
    let width = cgImage.width
    let height = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var rawData = [UInt8](repeating: 0, count: width * height * 4)
    
    let context = CGContext(data: &rawData,
                            width: width,
                            height: height,
                            bitsPerComponent: 8,
                            bytesPerRow: width * 4,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    let cx = width / 2
    let cy = height / 2
    let dialRadius: CGFloat = 298.5
    
    // Aggressively patch old dot at top-center
    // The old dot center was ~511, 268 (from top)
    let cgOldDotY = height - 268
    let cgOldDotX = 511
    
    // Sample a color safely far away from the dot but at the same Y level to match lighting
    let sampleOffset = (cgOldDotY * width + (cgOldDotX + 80)) * 4
    let r = CGFloat(rawData[sampleOffset]) / 255.0
    let g = CGFloat(rawData[sampleOffset+1]) / 255.0
    let b = CGFloat(rawData[sampleOffset+2]) / 255.0
    let patchColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
    
    context.setFillColor(patchColor.cgColor)
    
    // Use a much larger patch to completely obliterate any dark pixels or shadows from the old dot
    // A 120x120 patch with 15px blur will seamlessly blend it into the white dial
    context.setShadow(offset: .zero, blur: 20, color: patchColor.cgColor)
    context.fillEllipse(in: CGRect(x: cgOldDotX - 60, y: cgOldDotY - 60, width: 120, height: 120))
    // Fill it a second time without shadow to ensure the center is completely opaque
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.fillEllipse(in: CGRect(x: cgOldDotX - 45, y: cgOldDotY - 45, width: 90, height: 90))
    
    // Draw new dot at BOTTOM-LEFT
    let targetAngle = atan2(CGFloat(-7), CGFloat(-3))
    
    let newDotRadius = dialRadius / 10.0
    let newDotDistance = dialRadius * 0.75
    
    let newDotX = CGFloat(cx) + cos(targetAngle) * newDotDistance
    let newDotY = CGFloat(cy) + sin(targetAngle) * newDotDistance
    
    context.setFillColor(NSColor(white: 0.15, alpha: 1.0).cgColor)
    context.fillEllipse(in: CGRect(x: newDotX - newDotRadius, y: newDotY - newDotRadius, width: newDotRadius * 2, height: newDotRadius * 2))
    
    context.setStrokeColor(NSColor(white: 1.0, alpha: 0.8).cgColor)
    context.setLineWidth(3)
    context.addArc(center: CGPoint(x: newDotX, y: newDotY), radius: newDotRadius, startAngle: 0, endAngle: .pi, clockwise: true)
    context.strokePath()
    
    context.setStrokeColor(NSColor(white: 0.0, alpha: 0.5).cgColor)
    context.setLineWidth(3)
    context.addArc(center: CGPoint(x: newDotX, y: newDotY), radius: newDotRadius, startAngle: .pi, endAngle: .pi * 2, clockwise: true)
    context.strokePath()
    
    guard let newCgImage = context.makeImage() else { return }
    let nsImage = NSImage(cgImage: newCgImage, size: NSSize(width: width, height: height))
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
        return
    }
    
    try? pngData.write(to: URL(fileURLWithPath: "Icon-1024.png"))
    print("Successfully generated aggressively patched Icon-1024.png")
}

processIcon()
