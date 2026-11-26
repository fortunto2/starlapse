import CoreVideo
import Foundation
import SkyMeter
import StackKit

// The detector's path through the engine, split out when `StackEngine.swift` reached the
// file-length limit. Same queue contract: every call runs on the capture queue.
extension StackEngine {

    /// Hand the frame to the watcher, and keep the live view alive at a modest rate.
    func watch(_ frame: SensorFrame, watcher: SkyWatcher, plan: SegmentPlan) {
        accumulator.prepare(
            width: CVPixelBufferGetWidth(frame.pixelBuffer),
            height: CVPixelBufferGetHeight(frame.pixelBuffer)
        )

        // The live view, but not every frame. Watching runs for hours at four frames a
        // second with the screen dimmed and nobody looking; refreshing it each time wrote
        // and read back the full float32 accumulator — around 500 MB of GPU traffic per
        // frame — to redraw a picture of an empty sky.
        previewCountdown -= 1
        if previewCountdown <= 0 {
            previewCountdown = Self.watchPreviewInterval
            accumulator.add(frame.pixelBuffer, transform: nil, mode: plan.stackMode, replacingContents: true)
            if let rendered = accumulator.resolve(tone: plan.tone, mode: plan.stackMode) {
                publish(rendered)
            }
        }

        guard let luminance = accumulator.readLuminance(from: frame.pixelBuffer) else { return }
        reportFocusIfRequested(luminance)
        // Kept for the plate solve that orients the detector's meteors. An array is shared
        // until written, so this is a reference, not a copy.
        latestLuminance = LumaImage(pixels: luminance, width: accumulator.lumaWidth, height: accumulator.lumaHeight)

        switch watcher.consume(
            frame,
            luminance: luminance,
            width: accumulator.lumaWidth,
            height: accumulator.lumaHeight
        ) {
        case .waiting:
            break
        case .discarded:
            progress.eventsDetected += 1
        case .recorded(let url, let event):
            progress.eventsDetected += 1
            progress.eventsRecorded = watcher.eventsRecorded
            onEventRecorded?(url, event, LumaImage.Size(width: accumulator.lumaWidth, height: accumulator.lumaHeight))
        }
        report()
    }
}
