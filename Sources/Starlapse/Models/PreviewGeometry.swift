import CoreGraphics
import Foundation
import SkyKit
import SkyMeter

/// Where a direction on the sky lands on the screen, by the same camera model the plate
/// solver uses.
///
/// The overlay used to place markers with a flat "degrees × pixels per degree" sketch, and
/// two things in it were wrong, not just rough. It spread the lens's field of view across
/// the screen's width, but `videoFieldOfView` is measured across the sensor's *long* side
/// and a portrait screen shows the short one: 73° assumed where 58° is true on the main
/// lens, so a star 25° out was drawn about 4° short of itself. And it ignored roll: tilt
/// the phone and the sky on screen turned while the markers did not.
///
/// The preview is drawn aspect-fit into the same view the overlay lives in, and the buffer
/// is upright with the phone's own top (`videoRotationAngle` 90), so the mapping is the
/// buffer's pinhole projection scaled into the fitted rectangle — whatever way the
/// interface is rotated.
struct PreviewGeometry {

    let pointing: CameraPointing
    /// Where the preview image sits in the view: letterboxed, not cropped.
    let imageRect: CGRect

    /// - Parameters:
    ///   - lensFieldOfView: degrees across the sensor's long side.
    ///   - buffer: the preview buffer's size, portrait as delivered.
    ///   - fieldScale: the solved field over the published one, from a `SkyLock`; 1 without.
    init(
        aim: HorizontalCoordinates, imageRoll: Double, lensFieldOfView: Double, buffer: CGSize, view: CGSize,
        fieldScale: Double = 1
    ) {
        let scale = min(view.width / buffer.width, view.height / buffer.height)
        let fitted = CGSize(width: buffer.width * scale, height: buffer.height * scale)
        imageRect = CGRect(
            x: (view.width - fitted.width) / 2, y: (view.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height
        )
        let acrossWidth = Self.fieldAcrossWidth(lensFieldOfView: lensFieldOfView, buffer: buffer) * fieldScale
        pointing = CameraPointing(center: aim, roll: imageRoll, horizontalFieldOfView: acrossWidth)
    }

    /// Degrees across a buffer's width, from the lens's figure across the sensor's long side.
    static func fieldAcrossWidth(lensFieldOfView: Double, buffer: CGSize) -> Double {
        let longSide = max(buffer.width, buffer.height)
        let focal = longSide / 2 / tan((lensFieldOfView / 2).radians)
        return (2 * atan(buffer.width / 2 / focal)).degrees
    }

    /// The screen point for `direction`, or nil when it is behind the camera.
    func project(_ direction: HorizontalCoordinates) -> CGPoint? {
        // Projected at a fixed fine resolution, then scaled: CameraPointing works in whole
        // pixels, and a point-sized screen would round a star by up to half a point.
        let resolution = 4096.0
        let height = resolution * imageRect.height / imageRect.width
        guard let pixel = pointing.project(direction, width: Int(resolution), height: Int(height.rounded()))
        else { return nil }
        let scale = imageRect.width / resolution
        return CGPoint(x: imageRect.minX + pixel.x * scale, y: imageRect.minY + pixel.y * scale)
    }

    /// The image's roll, from where the world's up points in the phone's own axes (x to
    /// the right edge, y to the top edge, as the screen is held in portrait). Upright is 0;
    /// right edge up is −90, which turns what is above the centre toward the right.
    static func imageRoll(worldUpX: Double, worldUpY: Double) -> Double {
        -atan2(worldUpX, worldUpY).degrees
    }
}
