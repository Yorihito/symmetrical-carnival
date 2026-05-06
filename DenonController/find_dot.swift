import Cocoa

let inputPath = "/Users/ytada/.gemini/antigravity/brain/190512b6-7f79-4bb4-ba6b-85f9c956aab0/minimal_dial_app_icon_1778029611420.png"
guard let image = NSImage(contentsOfFile: inputPath),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }

let width = cgImage.width
let height = cgImage.height
var rawData = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

var sumX = 0
var sumY = 0
var count = 0
for y in 250...290 {
    for x in 490...530 {
        let offset = (y * width + x) * 4
        let gray = Int(rawData[offset]) + Int(rawData[offset+1]) + Int(rawData[offset+2])
        if gray < 600 {
            sumX += x
            sumY += y
            count += 1
        }
    }
}

if count > 0 {
    print("Dot center: \(sumX/count), \(sumY/count)")
} else {
    print("No dot found in targeted area")
}
