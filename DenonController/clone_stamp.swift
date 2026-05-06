import Cocoa
import Foundation

let inputPath = "/Users/ytada/.gemini/antigravity/brain/190512b6-7f79-4bb4-ba6b-85f9c956aab0/minimal_dial_app_icon_1778029611420.png"
guard let image = NSImage(contentsOfFile: inputPath),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    exit(1)
}

let width = cgImage.width
let height = cgImage.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
var rawData = [UInt8](repeating: 0, count: width * height * 4)

let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

// The array has Y=0 at BOTTOM because we drew into CGContext.
// The dot was at Y=268 from TOP, meaning cgY = 1024 - 268 = 756.
let targetX = 512
let targetY = 756
let patchRadius = 45 // 90x90 patch

// Source X: same Y, but far to the right (x=700) to get clean dial background
let sourceX = 700

for y in (targetY - patchRadius)...(targetY + patchRadius) {
    for x in (targetX - patchRadius)...(targetX + patchRadius) {
        let dx = CGFloat(x - targetX)
        let dy = CGFloat(y - targetY)
        let dist = sqrt(dx*dx + dy*dy)
        let r_max = CGFloat(patchRadius)
        
        if dist <= r_max {
            // Soft brush blending: alpha is 1 at center, 0 at edge
            let alpha = 1.0 - pow(dist / r_max, 2.0)
            
            // Read source pixel
            let sx = sourceX + Int(dx)
            let sy = y
            let srcOffset = (sy * width + sx) * 4
            let sr = CGFloat(rawData[srcOffset])
            let sg = CGFloat(rawData[srcOffset+1])
            let sb = CGFloat(rawData[srcOffset+2])
            
            // Read target pixel
            let targetOffset = (y * width + x) * 4
            let tr = CGFloat(rawData[targetOffset])
            let tg = CGFloat(rawData[targetOffset+1])
            let tb = CGFloat(rawData[targetOffset+2])
            
            // Blend
            rawData[targetOffset]   = UInt8(sr * alpha + tr * (1.0 - alpha))
            rawData[targetOffset+1] = UInt8(sg * alpha + tg * (1.0 - alpha))
            rawData[targetOffset+2] = UInt8(sb * alpha + tb * (1.0 - alpha))
        }
    }
}

// Now draw the new dot at bottom-left
let cx = width / 2
let cy = height / 2
let dialRadius: CGFloat = 298.5

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

guard let newCgImage = context.makeImage() else { exit(1) }
let nsImage = NSImage(cgImage: newCgImage, size: NSSize(width: width, height: height))
let tiffData = nsImage.tiffRepresentation!
let bitmapImage = NSBitmapImageRep(data: tiffData)!
let pngData = bitmapImage.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: "Icon-1024-test.png"))
print("Done")
