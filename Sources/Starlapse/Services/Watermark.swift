import CoreGraphics
import CoreText
import Foundation

/// "Shot on Starlapse" in the corner of what a free phone saves. Pro saves it clean.
///
/// The night sky is the content people post, and a post that names the app is the only
/// advertising a one-person app can afford: every shared time-lapse carries it. Small,
/// white at 70 %, bottom right, so it reads like a camera credit and not a stamp across
/// the stars. The dataset contribution always gets the clean frame — science does not
/// want our name in its pixels.
enum Watermark {

    static let text = "Shot on Starlapse"

    static func applies(isPro: Bool) -> Bool { !isPro }

    /// Draw the credit into a context the size of the frame. Coordinates are Core
    /// Graphics', so y = margin is the bottom of the picture.
    static func stamp(_ context: CGContext, width: Int, height: Int) {
        let size = max(12, CGFloat(min(width, height)) * 0.028)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 1, alpha: 0.7),
        ] as [CFString: Any] as CFDictionary
        guard let string = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
        let line = CTLineCreateWithAttributedString(string)
        let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: CGFloat(width) - CGFloat(textWidth) - size, y: size)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// A copy of the image with the credit drawn in. The original is left untouched.
    static func stamped(_ image: RenderedImage) -> RenderedImage {
        var pixels = image.pixels
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = context(
                over: buffer.baseAddress, width: image.width, height: image.height, bytesPerRow: image.bytesPerRow
            ) else { return }
            stamp(context, width: image.width, height: image.height)
        }
        return RenderedImage(pixels: pixels, width: image.width, height: image.height, bytesPerRow: image.bytesPerRow)
    }

    /// A bitmap context over BGRA8 memory, the format every stage of this pipeline speaks.
    static func context(
        over base: UnsafeMutableRawPointer?, width: Int, height: Int, bytesPerRow: Int
    ) -> CGContext? {
        CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
