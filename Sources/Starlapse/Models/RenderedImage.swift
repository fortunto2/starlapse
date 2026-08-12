import CoreGraphics
import Foundation
import UIKit

/// A finished frame as plain bytes, safe to hand to any actor.
///
/// GPU textures cannot cross an isolation boundary — the capture queue keeps writing into
/// them. This is the hand-off type: one copy at the end of a session, then the main actor
/// owns it outright.
struct RenderedImage: Sendable {
    let pixels: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int

    /// BGRA8, premultiplied — matching the display texture format.
    func makeCGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
                .union(.byteOrder32Little),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    func makeUIImage() -> UIImage? {
        makeCGImage().map { UIImage(cgImage: $0) }
    }
}
