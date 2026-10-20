import CoreGraphics
import Foundation
import SkyKit
import Testing
@testable import Starlapse

/// The overlay must put a star where the preview shows it: the right field of view across
/// the screen, and the sky turning with the phone.
@Suite("Preview geometry")
struct PreviewGeometryTests {

    /// The main lens: 73° across a 4:3 sensor's long side, shown portrait on a phone screen.
    private func geometry(roll: Double = 0, aim: HorizontalCoordinates = .init(azimuth: 180, altitude: 30))
        -> PreviewGeometry {
        PreviewGeometry(
            aim: aim, imageRoll: roll, lensFieldOfView: 73,
            buffer: CGSize(width: 1440, height: 1920), view: CGSize(width: 402, height: 874)
        )
    }

    @Test("The aim lands in the middle of the fitted image")
    func centre() throws {
        let geometry = geometry()
        let point = try #require(geometry.project(.init(azimuth: 180, altitude: 30)))
        #expect(abs(point.x - geometry.imageRect.midX) < 0.5)
        #expect(abs(point.y - geometry.imageRect.midY) < 0.5)
    }

    @Test("Aspect-fit: the image spans the width and is letterboxed top and bottom")
    func letterbox() {
        let rect = geometry().imageRect
        #expect(abs(rect.width - 402) < 0.01)
        #expect(abs(rect.height - 536) < 0.01)
        #expect(abs(rect.minY - 169) < 0.01)
    }

    @Test("The screen's width shows the sensor's short side, about 58°, not 73°")
    func widthIsTheShortSide() throws {
        let geometry = geometry(aim: .init(azimuth: 180, altitude: 0))
        let halfWidth = geometry.pointing.horizontalFieldOfView / 2
        #expect(abs(geometry.pointing.horizontalFieldOfView - 58.0) < 0.3)
        // A direction at half that field, on the horizon, sits on the right edge.
        let edge = try #require(geometry.project(.init(azimuth: 180 + halfWidth, altitude: 0)))
        #expect(abs(edge.x - geometry.imageRect.maxX) < 0.5)
    }

    @Test("Upright, higher in the sky is higher on screen")
    func upright() throws {
        let geometry = geometry()
        let above = try #require(geometry.project(.init(azimuth: 180, altitude: 40)))
        #expect(abs(above.x - geometry.imageRect.midX) < 0.5)
        #expect(above.y < geometry.imageRect.midY - 50)
    }

    @Test("Right edge up: what is above the aim turns to the right of the screen")
    func rolled() throws {
        let roll = PreviewGeometry.imageRoll(worldUpX: 1, worldUpY: 0)
        #expect(abs(roll + 90) < 1e-9)
        #expect(PreviewGeometry.imageRoll(worldUpX: 0, worldUpY: 1) == 0)

        let geometry = geometry(roll: roll)
        let above = try #require(geometry.project(.init(azimuth: 180, altitude: 40)))
        #expect(above.x > geometry.imageRect.midX + 50)
        #expect(abs(above.y - geometry.imageRect.midY) < 0.5)
    }

    @Test("Behind the camera is not drawn")
    func behind() {
        #expect(geometry().project(.init(azimuth: 0, altitude: -30)) == nil)
    }
}
