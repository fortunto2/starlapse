import Foundation
import Testing
@testable import Starlapse

/// The credit lands in the bottom-right corner of a free save, and nowhere else.
@Suite("Watermark")
struct WatermarkTests {

    private func blackImage(width: Int, height: Int) -> RenderedImage {
        RenderedImage(
            pixels: Data(count: width * height * 4), width: width, height: height, bytesPerRow: width * 4
        )
    }

    /// Brightest green channel inside a region, rows counted from the top of the picture.
    private func brightest(_ image: RenderedImage, rows: Range<Int>, columns: Range<Int>) -> UInt8 {
        var peak: UInt8 = 0
        for row in rows {
            for column in columns {
                peak = max(peak, image.pixels[row * image.bytesPerRow + column * 4 + 1])
            }
        }
        return peak
    }

    @Test("Free saves carry it, Pro saves do not")
    func policy() {
        #expect(Watermark.applies(isPro: false))
        #expect(!Watermark.applies(isPro: true))
    }

    @Test("Drawn in the bottom-right corner, the rest of the sky untouched")
    func placement() {
        let width = 1080, height = 1440
        let clean = blackImage(width: width, height: height)
        let credited = Watermark.stamped(clean)

        #expect(brightest(credited, rows: height - 120 ..< height, columns: width / 2 ..< width) > 100)
        #expect(brightest(credited, rows: 0 ..< height - 200, columns: 0 ..< width) == 0)
        #expect(brightest(credited, rows: height - 120 ..< height, columns: 0 ..< width / 4) == 0)
        // The original stays clean: the dataset gets the frame without our name in it.
        #expect(brightest(clean, rows: 0 ..< height, columns: 0 ..< width) == 0)
    }
}
