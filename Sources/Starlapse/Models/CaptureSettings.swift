import AVFoundation
import Foundation

/// One physical lens. The aperture is a fact about the glass, not a setting — this is the
/// single biggest misconception people bring from DSLR astrophotography. On iPhone you do
/// not open up the aperture; you pick the lens that is already open widest.
struct LensOption: Identifiable, Sendable, Hashable {
    var id: String { deviceType.rawValue }
    let deviceType: AVCaptureDevice.DeviceType
    let displayName: String
    /// Fixed f-number of this lens. Lower gathers more light.
    let aperture: Float
    /// Horizontal field of view in degrees — how much sky fits in one frame.
    let fieldOfView: Float

    /// Relative light-gathering versus the widest lens on the device, in stops.
    /// f/2.2 against f/1.78 is 0.6 stops darker, which over an hour of stacking is the
    /// difference between a faint Milky Way and a clear one.
    func stopsDarker(than reference: LensOption) -> Float {
        2 * log2(aperture / reference.aperture)
    }
}

/// How frames are combined. This is the choice that decides what the photo *is*, and it
/// happens to be reversible — the raw frames are kept, so the same hour of sky can be
/// rendered as pinpoint stars or as trails afterwards.
enum StackMode: String, CaseIterable, Sendable, Identifiable {
    /// Align every frame on the stars, then average. Stars stay points, noise falls as
    /// √N — 400 frames is a little over four stops of noise reduction. The ground blurs.
    case stars
    /// Keep the brightest value per pixel, no alignment. The sky's rotation draws arcs;
    /// the ground stays sharp. This is the classic star-trail look.
    case trails
    /// Average without aligning. Sky smears slightly, ground gets very clean — the right
    /// choice when the landscape is the subject and the stars are texture.
    case smooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stars: "Pinpoint stars"
        case .trails: "Star trails"
        case .smooth: "Clean landscape"
        }
    }

    var explanation: String {
        switch self {
        case .stars: "Frames aligned on the stars, then averaged. Stars stay sharp, noise drops as √N."
        case .trails: "Brightest pixel wins. The sky's rotation draws arcs, the ground stays sharp."
        case .smooth: "Averaged as shot. Stars trail a little, the landscape gets very clean."
        }
    }

    var alignsStars: Bool { self == .stars }
}

/// Everything the user controls. Deliberately explicit: nothing here is ever changed
/// behind their back, which is the whole complaint about every other camera app.
struct CaptureSettings: Sendable, Equatable {
    var lens: LensOption
    /// Sensor gain. Locked — the system never gets to drift it.
    var iso: Float
    /// Exposure of a single frame, seconds. Hardware-capped at roughly 1 s.
    var frameExposure: Double
    /// Lens position, 0…1. Astrophotography lives at 1.0 (infinity) and nowhere else.
    var focusPosition: Float
    /// White balance in kelvin. Around 3900 K keeps a night sky neutral instead of
    /// the orange cast auto-WB gives it under any sodium light.
    var whiteBalanceKelvin: Float
    var stackMode: StackMode
    /// Total light to collect, seconds. This is the number the user actually thinks in —
    /// "ten minutes" — and it is what makes exposures far past the 1 s hardware ceiling.
    var totalLightSeconds: Double

    static let minimumTotalLight: Double = 10
    static let maximumTotalLight: Double = 3600

    /// How many frames that adds up to. The honest translation of "a one-hour exposure"
    /// into what the hardware will really do.
    var frameCount: Int {
        max(1, Int((totalLightSeconds / frameExposure).rounded()))
    }

    /// Noise improvement from averaging, in stops. Only meaningful for the averaging modes.
    var noiseReductionStops: Double {
        guard stackMode != .trails else { return 0 }
        return log2(Double(frameCount).squareRoot())
    }

    /// How far the sky rotates during a single frame, in arcseconds, at the worst-case
    /// declination. Above roughly 30" stars stop being points even before stacking, which
    /// is the real reason frame exposure cannot simply be maxed out.
    ///
    /// The sky turns 15 arcseconds per second of time at the celestial equator.
    var starDriftArcseconds: Double {
        frameExposure * 15.0
    }

    static func `default`(for lens: LensOption, capabilities: CameraCapabilities) -> Self {
        CaptureSettings(
            lens: lens,
            // Native ISO on these sensors sits around 55; going far above it trades
            // dynamic range for nothing that stacking would not give you for free.
            iso: min(1600, capabilities.isoRange.upperBound / 2),
            frameExposure: capabilities.maxFrameExposure,
            focusPosition: 1.0,
            whiteBalanceKelvin: 3900,
            stackMode: .stars,
            totalLightSeconds: 300
        )
    }
}

/// What this particular iPhone can actually do, read from the hardware rather than assumed.
/// A 14 Pro Max and a 17 Pro do not agree on ISO ceilings or which formats allow the
/// longest frames, and hardcoding either one would be wrong on the other.
struct CameraCapabilities: Sendable {
    let lenses: [LensOption]
    let isoRange: ClosedRange<Float>
    /// Longest single-frame exposure the chosen format allows — about 1 s on modern
    /// iPhones. Everything longer is built by stacking.
    let maxFrameExposure: Double
    let minFrameExposure: Double
    let supportsAppleProRAW: Bool
    let deviceModel: String

    /// The widest-aperture lens: the default choice for any night shot.
    var fastestLens: LensOption? {
        lenses.min { $0.aperture < $1.aperture }
    }

    static let unavailable = CameraCapabilities(
        lenses: [],
        isoRange: 100...100,
        maxFrameExposure: 1,
        minFrameExposure: 1 / 1000,
        supportsAppleProRAW: false,
        deviceModel: "Unavailable"
    )
}
