import CoreVideo
import Foundation

/// A frame straight off the sensor, handed over on the capture queue.
///
/// Not `Sendable`: a `CVPixelBuffer` is a live reference into a finite pool, and the
/// contract is that the receiver consumes it synchronously — copy it into a Metal texture
/// and return. Holding one past the callback starves the pool and stalls capture.
struct SensorFrame {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
    let index: Int
}

protocol CameraServiceProtocol: AnyObject {
    var capabilities: CameraCapabilities { get }

    func requestAuthorization() async -> Bool
    func prepare() async throws
    func apply(_ settings: CaptureSettings) async throws
    func startStreaming() async throws
    func stopStreaming() async
}

enum CameraError: LocalizedError {
    case authorizationDenied
    case noCameraAvailable
    case noUsableFormat
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Camera access is off. Enable it in Settings › Starlapse."
        case .noCameraAvailable:
            "No usable rear camera on this device."
        case .noUsableFormat:
            "This camera has no format that allows long exposures."
        case .configurationFailed(let detail):
            "Camera setup failed: \(detail)"
        }
    }
}
