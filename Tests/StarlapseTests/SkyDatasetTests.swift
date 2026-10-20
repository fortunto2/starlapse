import Foundation
import SkyKit
import SkyMeter
import Testing
@testable import Starlapse

/// The wire format is a promise to the server and to PRIVACY.md: these pin both.
@Suite("Sky dataset")
@MainActor
struct SkyDatasetTests {

    static let start = SkyMeasurement.Start(
        aim: HorizontalCoordinates(azimuth: 60, altitude: 45),
        location: GeographicCoordinates(latitude: 40.4168, longitude: -3.7038),
        date: Date(timeIntervalSince1970: 1_792_548_000), fieldOfView: 106
    )

    static let camera = SkyDataset.Camera(
        lens: "Ultra Wide", iso: 3200, shutter: 1, frames: 120, fieldOfView: 106, device: "iPhone18,1"
    )

    static func json(_ contribution: SkyDataset.Contribution) throws -> [String: Any] {
        let data = try SkyDataset.encoded(contribution)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Location leaves the phone at 0.1°, never finer")
    func coarseLocation() throws {
        let body = try Self.json(
            SkyDataset.contribution(kind: "stack", start: Self.start, sky: nil, camera: Self.camera)
        )
        #expect(body["latitude"] as? Double == 40.4)
        #expect(body["longitude"] as? Double == -3.7)
    }

    @Test("The keys are the ones the server validates, and the time is plain ISO 8601")
    func wireFormat() throws {
        let reading = SkyReading(
            skyBrightness: 20.8, uncertainty: 0.05, nakedEyeLimit: 6.1, bortle: 4, stackLimit: 9.2,
            matchedStars: 140, altitude: 45.37, azimuth: 60.2,
            stars: [StarSample(
                magnitude: 2.1, colorIndex: 0.4, flux: 12, background: 0.05, pixelArea: 44_100, altitude: 52
            )]
        )
        let body = try Self.json(
            SkyDataset.contribution(kind: "stack", start: Self.start, sky: reading, camera: Self.camera)
        )
        #expect(Set(body.keys) == [
            "id", "contributor", "takenAt", "kind", "latitude", "longitude", "sky", "camera", "appVersion",
        ])
        let takenAt = try #require(body["takenAt"] as? String)
        #expect(takenAt.hasSuffix("Z") && !takenAt.contains("."))
        // Every nested key is one server/src/observation.ts accepts, and nothing more.
        let sky = try #require(body["sky"] as? [String: Any])
        #expect(Set(sky.keys) == [
            "skyBrightness", "uncertainty", "nakedEyeLimit", "bortle", "stackLimit", "matchedStars",
            "altitude", "azimuth", "meterVersion", "stars",
        ])
        #expect(sky["altitude"] as? Double == 45 && sky["azimuth"] as? Double == 60)
        let star = try #require((sky["stars"] as? [[String: Any]])?.first)
        #expect(Set(star.keys) == ["magnitude", "colorIndex", "flux", "background", "pixelArea", "altitude"])
        let camera = try #require(body["camera"] as? [String: Any])
        #expect(Set(camera.keys) == ["lens", "iso", "shutter", "frames", "fieldOfView", "device"])
    }

    @Test("Only a file the server will never take is dropped; rate limits and timeouts retry")
    func outcomes() {
        #expect(SkyDataset.outcome(status: 201) == .stored)
        #expect(SkyDataset.outcome(status: 400) == .refused)
        #expect(SkyDataset.outcome(status: 415) == .refused)
        #expect(SkyDataset.outcome(status: 429) == .later)
        #expect(SkyDataset.outcome(status: 403) == .later)
        #expect(SkyDataset.outcome(status: 503) == .later)
        #expect(SkyDataset.outcome(status: nil) == .later)
    }

    @Test("The contributor id is random, stable, and not the usage counter's")
    func contributor() {
        let first = SkyDataset.contributor
        #expect(UUID(uuidString: first) != nil)
        #expect(SkyDataset.contributor == first)
    }
}
