import Foundation
import SkyKit
import StackKit
import Testing
@testable import SkyMeter

/// A gnomonic camera maps great circles to straight lines, so a streak drawn along a line
/// through the frame centre, with the radiant at the centre, is a meteor from that radiant.
@Suite("Meteor astrometry")
struct MeteorObservationTests {

    /// 03:00 UTC on 21 October 2026, the Orionid maximum, from Madrid: Orion is high.
    static let moment: SkyMoment = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 3)) ?? .distantPast
        return SkyMoment(location: GeographicCoordinates(latitude: 40.4, longitude: -3.7), date: date)
    }()

    static func pointingAtRadiant(_ code: String) throws -> CameraPointing {
        let shower = try #require(MeteorShower.catalog.first { $0.code == code })
        let radiant = shower.radiant.horizontal(at: moment.location, date: moment.date)
        return CameraPointing(center: radiant, roll: 0, horizontalFieldOfView: 70)
    }

    @Test("A streak pointing back at the Orionid radiant is an Orionid, ordered away from it")
    func orionid() throws {
        let pointing = try Self.pointingAtRadiant("ORI")
        // Elongation 8 over 200 pixels: about 40 px long, centred 300 px out along a diagonal.
        let streak = Transient(x: 600 + 240, y: 450 + 180, pixelCount: 200, flux: 5, elongation: 8, angle: 36.87)
        let meteor = MeteorAstrometry.observe(
            streak, frame: LumaImage.Size(width: 1200, height: 900), pointing: pointing, moment: Self.moment
        )
        #expect(meteor.shower == "ORI")
        let radiant = pointing.center
        let start = HorizontalCoordinates(azimuth: meteor.startAzimuth, altitude: meteor.startAltitude)
        let end = HorizontalCoordinates(azimuth: meteor.endAzimuth, altitude: meteor.endAltitude)
        #expect(start.separation(from: radiant) < end.separation(from: radiant))
        #expect(meteor.length > 1 && meteor.length < 4)
    }

    @Test("A streak across the line to the radiant is not from it")
    func sporadic() throws {
        let pointing = try Self.pointingAtRadiant("ORI")
        // Perpendicular to the radial direction, 300 px out.
        let streak = Transient(x: 600 + 240, y: 450 + 180, pixelCount: 200, flux: 5, elongation: 8, angle: 126.87)
        let meteor = MeteorAstrometry.observe(
            streak, frame: LumaImage.Size(width: 1200, height: 900), pointing: pointing, moment: Self.moment
        )
        // It may still point back at another radiant (here it lines up with the Southern
        // Taurids, also active); what it must not be is an Orionid.
        #expect(meteor.shower != "ORI")
    }

    @Test("A streak whose line passes through the radiant between its ends is not from it")
    func radiantBetweenEnds() throws {
        let pointing = try Self.pointingAtRadiant("ORI")
        let streak = Transient(x: 600, y: 450, pixelCount: 2000, flux: 5, elongation: 8, angle: 0)
        let meteor = MeteorAstrometry.observe(
            streak, frame: LumaImage.Size(width: 1200, height: 900), pointing: pointing, moment: Self.moment
        )
        #expect(meteor.shower != "ORI")
    }
}
