import Cocoa
import Foundation

func findDotAngle(imagePath: String) -> CGFloat {
    guard let image = NSImage(contentsOfFile: imagePath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Could not load image")
        return .pi * 0.75 // Default fallback to 135 degrees (bottom-left)
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
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    
    context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    var minVal: UInt8 = 255
    var mx = width / 2
    var my = height / 2
    
    let cx = width / 2
    let cy = height / 2
    
    // Scan for darkest pixel that is NOT transparent
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let r = rawData[offset]
            let g = rawData[offset+1]
            let b = rawData[offset+2]
            let a = rawData[offset+3]
            
            if a > 128 { // Only consider non-transparent pixels
                let gray = UInt8((Int(r) + Int(g) + Int(b)) / 3)
                if gray < minVal {
                    minVal = gray
                    mx = x
                    my = y
                }
            }
        }
    }
    
    let dx = CGFloat(mx - cx)
    let dy = CGFloat(my - cy)
    
    print("Found darkest pixel at \(mx), \(my) with value \(minVal)")
    return atan2(dy, dx)
}

func createIcon(angle: CGFloat) {
    let size: CGFloat = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    
    guard let context = CGContext(data: nil,
                                  width: Int(size),
                                  height: Int(size),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo) else {
        return
    }
    
    // White background
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    
    // White dial
    let cx = size / 2
    let cy = size / 2
    let dialRadius = size * 0.42 // Slightly larger dial to look better
    
    // Subtle shadow for the dial
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: NSColor(white: 0, alpha: 0.15).cgColor)
    context.setFillColor(NSColor(white: 0.98, alpha: 1.0).cgColor)
    context.addArc(center: CGPoint(x: cx, y: cy), radius: dialRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()
    
    // Thin gray/black border
    context.setShadow(offset: CGSize.zero, blur: 0, color: nil) // clear shadow
    context.setStrokeColor(NSColor(white: 0.85, alpha: 1.0).cgColor)
    context.setLineWidth(2)
    context.addArc(center: CGPoint(x: cx, y: cy), radius: dialRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    
    // Dot size: 1/10 of white circle diameter
    // white circle diameter = dialRadius * 2
    // dot diameter = (dialRadius * 2) / 10 = dialRadius / 5
    // dot radius = dialRadius / 10
    let dotRadius = dialRadius / 10.0
    
    // Place it near the edge
    let dotDistance = dialRadius * 0.70
    let dotX = cx + cos(angle) * dotDistance
    let dotY = cy + sin(angle) * dotDistance
    
    // Recessed dot
    // Draw an inner shadow or just a dark circle with a light bottom edge
    context.setFillColor(NSColor(white: 0.15, alpha: 1.0).cgColor)
    context.addArc(center: CGPoint(x: dotX, y: dotY), radius: dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()
    
    // Light highlight at the bottom of the dot to make it look recessed
    context.setStrokeColor(NSColor(white: 1.0, alpha: 0.8).cgColor)
    context.setLineWidth(3)
    context.addArc(center: CGPoint(x: dotX, y: dotY), radius: dotRadius, startAngle: 0, endAngle: .pi, clockwise: true)
    context.strokePath()
    
    // Dark shadow at the top of the dot
    context.setStrokeColor(NSColor(white: 0.0, alpha: 0.5).cgColor)
    context.setLineWidth(3)
    context.addArc(center: CGPoint(x: dotX, y: dotY), radius: dotRadius, startAngle: .pi, endAngle: .pi * 2, clockwise: true)
    context.strokePath()
    
    guard let cgImage = context.makeImage() else { return }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
        return
    }
    
    try? pngData.write(to: URL(fileURLWithPath: "Icon-1024.png"))
    print("Successfully generated Icon-1024.png")
}

let angle = findDotAngle(imagePath: "DenonController/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png")
print("Using angle: \(angle) radians")
createIcon(angle: angle)
