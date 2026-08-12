import CoreVideo
import Foundation

/// The last few seconds of sky, kept in memory at all times.
///
/// A meteor lasts under a second, and by the time anything has detected one it is already
/// gone. Reacting is hopeless; the only way to film one is to have been filming already.
/// So frames are copied into a ring continuously, and when the detector fires the clip is
/// assembled from what has *already* happened — the event lands in the middle of the clip
/// instead of missing the start of it.
///
/// Memory is the constraint that shapes everything here. A full-resolution frame is ~48 MB;
/// three seconds of those would be over a gigabyte. That is why the detector runs the
/// camera at a smaller format — see `CaptureEngine.FormatPreference.detector`.
final class FrameRingBuffer: @unchecked Sendable {

    struct Entry {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
    }

    private let capacity: Int
    private var buffers: [CVPixelBuffer] = []
    private var timestamps: [TimeInterval] = []
    private var writeIndex = 0
    private var filled = 0
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0

    /// Seconds of history this ring holds at a given frame rate.
    let duration: TimeInterval

    init(seconds: TimeInterval, frameRate: Double) {
        duration = seconds
        capacity = max(2, Int((seconds * frameRate).rounded()))
    }

    var frameCount: Int { filled }

    /// Copy a frame into the ring, evicting the oldest.
    ///
    /// The copy is deliberate: the incoming buffer belongs to AVFoundation's pool and must
    /// be handed back when the callback returns. Holding it would starve capture within a
    /// few frames.
    func append(_ source: CVPixelBuffer, timestamp: TimeInterval) {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)

        if width != sourceWidth || height != sourceHeight || pool == nil {
            configure(width: sourceWidth, height: sourceHeight)
        }
        guard let pool, buffers.count == capacity else { return }

        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
              let destination else { return }

        copy(from: source, to: destination)

        buffers[writeIndex] = destination
        timestamps[writeIndex] = timestamp
        writeIndex = (writeIndex + 1) % capacity
        filled = min(filled + 1, capacity)
    }

    /// Everything currently held, oldest first.
    func history() -> [Entry] {
        guard filled > 0 else { return [] }
        let start = filled == capacity ? writeIndex : 0
        return (0..<filled).map { offset in
            let index = (start + offset) % capacity
            return Entry(pixelBuffer: buffers[index], timestamp: timestamps[index])
        }
    }

    func removeAll() {
        filled = 0
        writeIndex = 0
    }

    // MARK: - Allocation

    private func configure(width: Int, height: Int) {
        self.width = width
        self.height = height

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var created: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &created)
        pool = created

        guard let pool = created else { return }

        // Allocate the whole ring up front. Doing it lazily would put a malloc of several
        // megabytes on the capture queue at an unpredictable moment.
        buffers = []
        timestamps = []
        buffers.reserveCapacity(capacity)
        for _ in 0..<capacity {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let buffer else {
                buffers = []
                return
            }
            buffers.append(buffer)
            timestamps.append(0)
        }
        filled = 0
        writeIndex = 0
    }

    private func copy(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        guard let from = CVPixelBufferGetBaseAddress(source),
              let to = CVPixelBufferGetBaseAddress(destination) else { return }

        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        let rowBytes = min(sourceStride, destinationStride)
        let rows = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(destination))

        if sourceStride == destinationStride {
            memcpy(to, from, rowBytes * rows)
        } else {
            for row in 0..<rows {
                memcpy(
                    to.advanced(by: row * destinationStride),
                    from.advanced(by: row * sourceStride),
                    rowBytes
                )
            }
        }
    }
}
