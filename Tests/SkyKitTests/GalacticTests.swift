import Foundation
import Testing
@testable import SkyKit

/// The galactic frame is pinned to the IAU definition, not to our own output: the centre,
/// the pole and the two points 90° along the plane have published J2000 coordinates.
@Suite("Galactic frame")
struct GalacticTests {

    private func expect(
        _ point: EquatorialCoordinates, raDegrees: Double, dec: Double, within tolerance: Double = 0.5
    ) {
        let raError = abs((point.rightAscension - raDegrees).signedDegrees)
        #expect(raError < tolerance, "RA \(point.rightAscension) vs \(raDegrees)")
        #expect(abs(point.declination - dec) < tolerance, "Dec \(point.declination) vs \(dec)")
    }

    @Test("Galactic centre lands in Sagittarius at 17h45m, -28.9°")
    func centre() {
        expect(GalacticCoordinates(longitude: 0, latitude: 0).equatorial, raDegrees: 266.405, dec: -28.936)
    }

    @Test("North galactic pole sits in Coma Berenices")
    func pole() {
        expect(GalacticCoordinates(longitude: 0, latitude: 90).equatorial, raDegrees: 192.859, dec: 27.128)
    }

    @Test("A quarter turn along the plane reaches Cygnus, the anticentre Auriga")
    func quarterTurns() {
        expect(GalacticCoordinates(longitude: 90, latitude: 0).equatorial, raDegrees: 318.004, dec: 48.330)
        expect(GalacticCoordinates(longitude: 180, latitude: 0).equatorial, raDegrees: 86.405, dec: 28.936)
        expect(GalacticCoordinates(longitude: 270, latitude: 0).equatorial, raDegrees: 138.004, dec: -48.330)
    }

    @Test("The sampled equator starts at the centre, is brightest there, and stays on the plane")
    func sampledEquator() {
        let band = SkyCatalog.galacticEquator()
        #expect(band.count == 36)
        #expect(band[0].brightness == 1.0)
        #expect(band.min { $0.brightness < $1.brightness }?.longitude == 180)
        expect(band[0].position, raDegrees: 266.405, dec: -28.936)
        #expect(SkyCatalog.milkyWayPlane.count == 12)
    }
}
