import Foundation
#if canImport(Vision)
import Vision
#endif

/// Is this photo a night sky with nobody in it? Asked before a photo joins the open dataset.
///
/// The first month of contributions (85 photos, 24 Nov 2026) held a person's face indoors, a
/// hand, a parked car, a laptop, two living rooms and daylight landscapes: anything saved as a
/// stack was uploaded. Star counts and brightness cannot tell these apart (JPEG noise reads as
/// 150 "stars" in a dark room), but Apple's scene classifier and its people detectors can, on
/// the phone, with nothing sent anywhere. The thresholds below were set on those 85 photos:
/// every night-sky frame passes except a few twilight and palm-frond shots, and none of the
/// people, rooms, objects or daylight frames do.
///
/// Best effort, not a guarantee: Vision misses small, distant or silhouetted people, which
/// are exactly the people in a Milky Way shot. It removes the obvious cases; it does not make
/// a photo anonymous.
public enum PhotoScreen {

    /// What Vision reports for one image.
    public struct Signals: Sendable, Equatable {
        public var nightSky: Float
        public var people: Float
        public var faces: Int
        public var humans: Int
        public var hands: Int

        public init(nightSky: Float, people: Float = 0, faces: Int = 0, humans: Int = 0, hands: Int = 0) {
            self.nightSky = nightSky
            self.people = people
            self.faces = faces
            self.humans = humans
            self.hands = hands
        }
    }

    /// Lowest `night_sky` confidence a frame needs. Measured: real night frames 0.25…0.93,
    /// the dark living room 0.01, the parked cars 0.03.
    public static let minimumNightSky: Float = 0.25
    /// Any `people` label at or above this keeps the photo private. One false alarm in 85
    /// (a night sky at 0.18), which costs a photo, not a person's privacy.
    public static let maximumPeople: Float = 0.15

    public static func isPublishableSky(_ signals: Signals) -> Bool {
        signals.faces == 0 && signals.humans == 0 && signals.hands == 0
            && signals.people < maximumPeople
            && signals.nightSky >= minimumNightSky
    }

    /// Run Vision on an encoded image. Nil when Vision could not run, which callers treat as
    /// "not publishable": a photo nobody looked at does not go out.
    public static func signals(of image: Data) -> Signals? {
        #if canImport(Vision)
        let handler = VNImageRequestHandler(data: image)
        let classify = VNClassifyImageRequest()
        let faces = VNDetectFaceRectanglesRequest()
        let humans = VNDetectHumanRectanglesRequest()
        let hands = VNDetectHumanHandPoseRequest()
        do {
            try handler.perform([classify, faces, humans, hands])
        } catch {
            return nil
        }
        let labels = classify.results ?? []
        func confidence(_ name: String) -> Float { labels.first { $0.identifier == name }?.confidence ?? 0 }
        return Signals(
            nightSky: confidence("night_sky"),
            people: confidence("people"),
            faces: faces.results?.count ?? 0,
            humans: humans.results?.count ?? 0,
            hands: hands.results?.count ?? 0
        )
        #else
        return nil
        #endif
    }

    public static func isPublishableSky(_ image: Data) -> Bool {
        signals(of: image).map(isPublishableSky) ?? false
    }
}
