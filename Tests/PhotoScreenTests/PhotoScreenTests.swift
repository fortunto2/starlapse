import PhotoScreen
import Testing

/// The rule against what Vision reported for real contributions (24 Nov 2026). Each case is
/// one photo from that month, by its number in the review sheet.
@Suite("Only night skies with nobody in them are published")
struct PhotoScreenTests {

    @Test("Night skies pass", arguments: [
        PhotoScreen.Signals(nightSky: 0.93),                // 028, Milky Way
        PhotoScreen.Signals(nightSky: 0.61),                // 044, sky over rooftops
        PhotoScreen.Signals(nightSky: 0.25),                // 047, faint stars
    ])
    func nightSkyPasses(_ signals: PhotoScreen.Signals) {
        #expect(PhotoScreen.isPublishableSky(signals))
    }

    @Test("People, rooms, objects and daylight stay private", arguments: [
        PhotoScreen.Signals(nightSky: 0.01, people: 0.84, faces: 1, hands: 1), // 035, a person indoors
        PhotoScreen.Signals(nightSky: 0.00, people: 0.18, hands: 1),           // 075, a living room
        PhotoScreen.Signals(nightSky: 0.00),                                   // 010, a hand; 076, a room
        PhotoScreen.Signals(nightSky: 0.03),                                   // 073, parked cars
        PhotoScreen.Signals(nightSky: 0.00),                                   // 007, daylight
        PhotoScreen.Signals(nightSky: 0.45, people: 0.18),                     // 071, sky but "people"
        PhotoScreen.Signals(nightSky: 0.80, faces: 1),                         // any face vetoes
    ])
    func privateStays(_ signals: PhotoScreen.Signals) {
        #expect(!PhotoScreen.isPublishableSky(signals))
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// Through Vision itself, so a renamed label or a shifted classifier shows up here rather
    /// than as a dataset that quietly stopped receiving photos.
    @Test("Vision passes a star field and refuses a flat frame")
    func throughVision() throws {
        let sky = try #require(PhotoScreen.signals(of: Self.fixture("star-field")))
        #expect(sky.nightSky >= PhotoScreen.minimumNightSky)
        #expect(PhotoScreen.isPublishableSky(sky))
        #expect(!PhotoScreen.isPublishableSky(try Self.fixture("flat-cyan")))
    }

    @Test("A photo Vision could not read is not published")
    func unreadable() {
        #expect(!PhotoScreen.isPublishableSky(Data([0, 1, 2])))
    }
}

import Foundation
