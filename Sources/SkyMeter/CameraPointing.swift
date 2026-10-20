import Foundation
import SkyKit

/// Where the phone was looking, and how wide: enough to say where any star should land.
///
/// The model is a pinhole (gnomonic) camera. The ultra-wide lens is not one, but iOS
/// corrects its distortion before the frame reaches us, and the residual is absorbed by
/// the similarity fit in `PlateMatch`. Image coordinates: x right, y down, in pixels of
/// the buffer being measured.
public struct CameraPointing: Sendable, Hashable {
    /// The direction of the frame centre.
    public var center: HorizontalCoordinates
    /// Degrees the camera is rolled; positive turns the image counter-clockwise on screen.
    public var roll: Double
    /// Degrees across the buffer's width.
    public var horizontalFieldOfView: Double

    public init(center: HorizontalCoordinates, roll: Double, horizontalFieldOfView: Double) {
        self.center = center
        self.roll = roll
        self.horizontalFieldOfView = horizontalFieldOfView
    }

    /// Focal length in pixels for a buffer this wide.
    public func focalLength(width: Int) -> Double {
        Double(width) / 2 / tan((horizontalFieldOfView / 2).radians)
    }

    /// Where `direction` lands in a `width`×`height` buffer, or nil behind the camera.
    public func project(_ direction: HorizontalCoordinates, width: Int, height: Int) -> (x: Double, y: Double)? {
        let azimuth0 = center.azimuth.radians
        let altitude0 = center.altitude.radians
        let azimuth = direction.azimuth.radians
        let altitude = direction.altitude.radians
        let deltaAzimuth = azimuth - azimuth0

        let cosC = sin(altitude0) * sin(altitude) + cos(altitude0) * cos(altitude) * cos(deltaAzimuth)
        guard cosC > 0.05 else { return nil }
        let xi = cos(altitude) * sin(deltaAzimuth) / cosC
        let eta = (cos(altitude0) * sin(altitude) - sin(altitude0) * cos(altitude) * cos(deltaAzimuth)) / cosC

        let rollAngle = roll.radians
        let planeX = xi * cos(rollAngle) - eta * sin(rollAngle)
        let planeY = xi * sin(rollAngle) + eta * cos(rollAngle)
        let focal = focalLength(width: width)
        return (Double(width) / 2 + focal * planeX, Double(height) / 2 - focal * planeY)
    }

    /// The direction a pixel looks at: the inverse of `project`.
    public func direction(x: Double, y: Double, width: Int, height: Int) -> HorizontalCoordinates {
        let focal = focalLength(width: width)
        let planeX = (x - Double(width) / 2) / focal
        let planeY = (Double(height) / 2 - y) / focal
        let rollAngle = roll.radians
        let xi = planeX * cos(rollAngle) + planeY * sin(rollAngle)
        let eta = -planeX * sin(rollAngle) + planeY * cos(rollAngle)

        let altitude0 = center.altitude.radians
        let rho = (xi * xi + eta * eta).squareRoot()
        guard rho > 1e-12 else { return center }
        let angle = atan(rho)
        let altitude = asin(cos(angle) * sin(altitude0) + eta * sin(angle) * cos(altitude0) / rho)
        let deltaAzimuth = atan2(
            xi * sin(angle), rho * cos(altitude0) * cos(angle) - eta * sin(altitude0) * sin(angle)
        )
        return HorizontalCoordinates(
            azimuth: center.azimuth + deltaAzimuth.degrees, altitude: altitude.degrees
        )
    }

    /// The solid angle of one pixel at `(x, y)`, in square arcseconds. A flat sensor
    /// behind a pinhole sees less sky per pixel off-axis, by cos³ of the angle.
    public func pixelArea(x: Double, y: Double, width: Int, height: Int) -> Double {
        let focal = focalLength(width: width)
        let dx = (x - Double(width) / 2) / focal
        let dy = (y - Double(height) / 2) / focal
        let cosine = 1 / (1 + dx * dx + dy * dy).squareRoot()
        let scale = 206_264.806 / focal
        return scale * scale * cosine * cosine * cosine
    }
}

/// A linear luminance buffer, row-major, mean light per pixel.
public struct LumaImage: Sendable {
    public let pixels: [Float]
    public let width: Int
    public let height: Int

    public init(pixels: [Float], width: Int, height: Int) {
        self.pixels = pixels
        self.width = width
        self.height = height
    }
}

/// Where and when: what turns a catalogue position into a direction in the sky.
public struct SkyMoment: Sendable, Hashable {
    public let location: GeographicCoordinates
    public let date: Date

    public init(location: GeographicCoordinates, date: Date) {
        self.location = location
        self.date = date
    }
}
