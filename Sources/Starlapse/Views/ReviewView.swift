import AVKit
import SwiftUI

/// What you get after the shutter closes: the result, the controls that still matter, and
/// a decision.
///
/// Nothing has been written to Photos yet. For a stack the curve is still live — the
/// accumulator holds the summed frames in float32, so dragging the stretch slider
/// re-develops from the original light instead of pushing an already-developed JPEG around.
/// That is the same latitude a RAW file gives you, and it is worth more here than anywhere
/// else: nobody can judge a night sky exposure on a phone screen in the dark.
struct ReviewView: View {

    @Bindable var model: CaptureViewModel
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.mode.isDetector {
                eventList
            } else if let url = model.reviewVideoURL {
                videoPlayer(url: url)
            } else {
                Spacer(minLength: 0)
                curveControls
            }

            actions
        }
        .background(NightTheme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(NightTheme.mono(12, weight: .bold))
                    .foregroundStyle(NightTheme.primary)
                Text(summary)
                    .font(NightTheme.mono(10))
                    .foregroundStyle(NightTheme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summary: String {
        if model.mode.isDetector {
            let clips = model.events.count
            return clips == 0
                ? "Nothing crossed the frame"
                : "\(clips) clip\(clips == 1 ? "" : "s") · \(model.progress.eventsDetected) detected"
        }
        if model.reviewVideoURL != nil {
            return "\(model.progress.segmentsCompleted) frames · "
                + String(format: "%.1fs", model.timelapse.videoDuration)
        }
        var parts = ["\(model.progress.framesStacked) frames"]
        if model.progress.noiseReductionStops > 0 {
            parts.append(String(format: "−%.1f stops noise", model.progress.noiseReductionStops))
        }
        if model.progress.framesRejected > 0 {
            parts.append("\(model.progress.framesRejected) dropped")
        }
        return parts.joined(separator: " · ")
    }

    private var headline: String {
        if model.mode.isDetector { return "WATCH ENDED" }
        return model.reviewVideoURL == nil ? "STACK COMPLETE" : "TIME-LAPSE COMPLETE"
    }

    // MARK: - Events

    private var eventList: some View {
        Group {
            if model.events.isEmpty {
                VStack(spacing: 6) {
                    Text("No events")
                        .font(NightTheme.mono(13, weight: .semibold))
                        .foregroundStyle(NightTheme.dim)
                    Text("A quiet sky, or the threshold is too strict.")
                        .font(NightTheme.mono(10))
                        .foregroundStyle(NightTheme.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.events) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func eventRow(_ event: CaptureViewModel.RecordedEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.isStreak ? "line.diagonal" : "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(event.isStreak ? NightTheme.accent : NightTheme.dim)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.isStreak ? "Streak" : "Flash")
                    .font(NightTheme.mono(12, weight: .semibold))
                    .foregroundStyle(NightTheme.primary)
                Text(event.date.formatted(date: .omitted, time: .standard)
                     + String(format: " · %.0f° across frame", event.angle))
                    .font(NightTheme.mono(9))
                    .foregroundStyle(NightTheme.dim)
            }

            Spacer()

            ShareLink(item: event.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundStyle(NightTheme.secondary)
            }
        }
        .padding(10)
        .background(NightTheme.background.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(NightTheme.dim.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Video

    private func videoPlayer(url: URL) -> some View {
        VideoPlayer(player: player)
            .aspectRatio(contentMode: .fit)
            .onAppear {
                let player = AVPlayer(url: url)
                // Night time-lapses are seconds long; looping makes them watchable without
                // reaching for a control every two seconds.
                player.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                self.player = player
                player.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }

    // MARK: - Curve

    private var curveControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEVELOP")
                .font(NightTheme.mono(11, weight: .bold))
                .foregroundStyle(NightTheme.secondary)

            NightSlider(
                label: "Stretch (asinh)",
                value: Binding(
                    get: { Double(model.reviewTone.stretch) },
                    set: { model.reviewTone.stretch = Float($0); model.reviewToneChanged() }
                ),
                range: 1...200,
                format: { String(format: "%.0f", $0) }
            )

            NightSlider(
                label: "Black point",
                value: Binding(
                    get: { Double(model.reviewTone.blackPoint) },
                    set: { model.reviewTone.blackPoint = Float($0); model.reviewToneChanged() }
                ),
                range: 0...0.3,
                format: { String(format: "%.3f", $0) }
            )

            NightSlider(
                label: "Exposure",
                value: Binding(
                    get: { Double(model.reviewTone.exposure) },
                    set: { model.reviewTone.exposure = Float($0); model.reviewToneChanged() }
                ),
                range: 0.1...8,
                format: { String(format: "%.2f×", $0) }
            )

            NightSlider(
                label: "Saturation",
                value: Binding(
                    get: { Double(model.reviewTone.saturation) },
                    set: { model.reviewTone.saturation = Float($0); model.reviewToneChanged() }
                ),
                range: 0...2.5,
                format: { String(format: "%.2f", $0) }
            )

            Text("Re-developed from the stacked frames, not from the preview — push it as far as you like.")
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.dim)
        }
        .padding(16)
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if let message = model.lastSavedMessage {
                Text(message)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        if model.mode.isDetector { model.clearEvents() }
                        await model.dismissReview()
                    }
                } label: {
                    Text("Discard")
                        .font(NightTheme.mono(13, weight: .semibold))
                        .foregroundStyle(NightTheme.dim)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(NightTheme.dim.opacity(0.5), lineWidth: 1)
                        )
                }

                Button {
                    Task {
                        if model.mode.isDetector {
                            await model.saveAllEvents()
                        } else {
                            await model.saveResult()
                        }
                        await model.dismissReview()
                    }
                } label: {
                    Text(model.mode.isDetector ? "Save \(model.events.count) to Photos" : "Save to Photos")
                        .font(NightTheme.mono(13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(NightTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
    }
}
