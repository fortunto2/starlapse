import CoreGraphics
import Foundation
import ImageIO
import StackKit

/// A photo file as linear luminance, the input the detector and the meter read. Mac-only,
/// which is fine for a CLI: the package targets stay platform-free.
struct PhotoLuma {
    let pixels: [Float]
    let width: Int
    let height: Int

    static func load(_ path: String, maxSide: Int = 1024) -> PhotoLuma? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let scale = min(1, Double(maxSide) / Double(max(full.width, full.height)))
        let width = max(1, Int(Double(full.width) * scale)), height = max(1, Int(Double(full.height) * scale))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let red = TransferFunction.sRGB.decode(Float(rgba[index * 4]) / 255)
            let green = TransferFunction.sRGB.decode(Float(rgba[index * 4 + 1]) / 255)
            let blue = TransferFunction.sRGB.decode(Float(rgba[index * 4 + 2]) / 255)
            pixels[index] = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return PhotoLuma(pixels: pixels, width: width, height: height)
    }
}
