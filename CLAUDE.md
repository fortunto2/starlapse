# CLAUDE.md — Starlapse

Long-exposure astrophotography for iPhone: manual camera control, frame stacking, star
alignment, night time-lapse, and a dark-sky aiming overlay.

## The three facts this app is built around

Read these before changing anything in `Services/`. Every architectural decision follows
from them, and each one contradicts an assumption people bring from DSLR astrophotography.

1. **Aperture is not adjustable.** iPhone lenses have fixed apertures. "Opening up" means
   picking a faster lens (main ≈ f/1.78 vs ultra-wide f/2.2), nothing more.
2. **A single frame caps at ~1 second.** `activeFormat.maxExposureDuration` is the hard
   ceiling; Night mode's 30 s is private API. Everything longer is **stacked**, not held.
   `CaptureSettings.totalLightSeconds` is the user's intent; `frameCount` is the truth.
3. **Capture cannot run in the background.** iOS force-stops `AVCaptureSession` when the
   app backgrounds. The substitute is `isIdleTimerDisabled` plus screen brightness at 0.05
   and a red-on-black UI. Do not add `UIBackgroundModes` — it buys nothing and risks review.

## Stack

Swift 6 (strict concurrency, `complete`) · SwiftUI · Metal · AVFoundation · CoreMotion ·
XcodeGen · SPM · Swift Testing · SwiftLint · iOS 18+ · Xcode 26

## Layout

```
Package.swift            SkyKit + StackKit + CLI — platform-free domain, testable on a Mac
Sources/
  SkyKit/                where things are in the sky; what is worth shooting tonight
  StackKit/              star detection + frame registration (pure Float math)
  SkyKitCLI/             `starlapse-sky` — CLI-first entry to the domain
  Starlapse/
    App/                 @main
    Models/              CaptureSettings, TimelapseSettings, AimGuidance
    Services/            CaptureEngine, FrameAccumulator, StackEngine, TimelapseWriter,
                         AttitudeProvider, Shaders/Stacking.metal
    ViewModels/          CaptureViewModel (@Observable @MainActor)
    Views/               CaptureView, ManualControlsView, SkyOverlayView, NightTheme
Tests/                   SkyKitTests (19), StackKitTests (8)
```

## Commands

`make help` lists everything. The ones that matter:

```bash
make test          # SPM tests — 27, run in ~3s on a Mac, no simulator
make integration   # CLI against the domain: tonight's aiming advice
make build         # simulator build (compile check)
make install       # build for device + install on the paired iPhone
make lint          # SwiftLint, currently zero warnings
```

## Concurrency model

Swift 6 strict mode is on, so this is not optional reading.

- `CaptureEngine`, `FrameAccumulator`, `StackEngine`, `TimelapseWriter` are
  `@unchecked Sendable` **by contract**: every method runs on the single capture queue.
  AVFoundation and Metal are queue-confined by design; wrapping them in actors would
  suspend on blocking calls and gain nothing.
- `CaptureViewModel` and `AttitudeProvider` are `@MainActor @Observable`.
- **Frames are pushed, never pulled.** The main actor must never call into the accumulator
  to render something. The first version did — `refreshPreview()` resolved on the main
  thread while the capture queue was mid-frame, sharing one command queue and one display
  texture — and it crashed at the end of every session. Now `StackEngine` pushes
  `PreviewFrame` as each render completes, and the accumulator alternates between **two**
  display textures so the one handed over is never the one being written.
- **Never send a bare `MTLTexture` or `CVPixelBuffer` across an isolation boundary.**
  `PreviewFrame` is `@unchecked Sendable` under the double-buffering guarantee documented
  on the type; `onSegmentReady` must consume its texture synchronously; `onFinished`
  carries a `RenderedImage` (plain `Data`), not GPU memory.

## The crash that took three tries

Symptom: the app died at the end of every shoot. Two rounds of fixes went into the Metal
pipeline — both found real races, neither stopped the crash. The third round pulled the
crash report off the device, and it named the culprit in one frame:

```
_dispatch_assert_queue_fail
swift_task_isCurrentExecutorWithFlagsImpl
closure #1 in CaptureViewModel.save(image:)
PHPhotoLibrary _performCancellableChanges
```

**A third-party API's callback block, written inline inside a `@MainActor` method, inherits
main-actor isolation.** Swift 6 then emits a runtime executor check inside that block. When
the API runs it on its own queue — as `PHPhotoLibrary.performChanges` does — the check fires
and SIGTRAPs the process. The fix is `nonisolated` on the function that owns the call.

Two rules from this:

1. Any framework callback that is not documented to run on the main queue must be reached
   from a `nonisolated` function. Grep before adding one: `performChanges`,
   `addCompletedHandler`, delegate callbacks, completion handlers.
2. **Pull the crash report before theorising.** `xcrun devicectl device info files --device
   <uuid> --domain-type systemCrashLogs` lists them; `devicectl device copy from` fetches
   one. Symptom-shaped reasoning ("it dies when capture ends, so it's the renderer") cost
   two full rounds of work on the wrong subsystem.

## Lessons from the first field test

Three failures, all in the layer that no test could reach. They are listed because each
one has a general form worth remembering:

1. **Black screen.** `StackEngine` dropped every frame until a session began, so the
   framing preview had nothing to show. A live state was assumed by the view model and
   never implemented by the engine. → `Activity.live`.
2. **Crash after capture.** The main/capture-queue race above. Compiling under strict
   concurrency does not save you when the types are `@unchecked Sendable` — the unchecked
   part is a promise, and that promise was being broken.
3. **Unreadable text.** `dim` was `(0.42, 0.09, 0.07)` at screen brightness 0.05. Red-on-
   black protects dark adaptation, which is real and valuable, but text nobody can read
   protects nothing. → white by default, red behind a toggle, brightness 0.2.

A `MTLBlitCommandEncoder` does not scale, either — it copied the corner of a 4032px frame
into the drawable, which looks exactly like a broken camera. Presentation goes through a
render pass with aspect-fit sampling.

## Testing

The domain is separated from the platform precisely so it can be tested without a device:

- **Sky math** is anchored to external facts, not to itself — Polaris sits at the pole,
  the synodic month falls out of the periodic terms, the Moon is new on the day of the
  2026-08-12 solar eclipse.
- **Alignment** is tested against synthetic star fields rotated by a known angle, because
  a subtly misaligned stack just looks like a slightly soft photo and you find out in a
  field at 2am.
- Never write a raw `timeIntervalSince1970` constant in a test. Use `Self.utc(y, m, d, h)`.
  The first draft had four such constants and three pointed at the wrong day.

## Don't

- Don't re-enable any automatic camera behaviour (HDR, stabilisation, low-light boost,
  subject-area monitoring, continuous AF/AE). Locking them is the whole product.
- Don't stack a frame whose alignment failed — drop it. One frame of lost light costs far
  less than a smeared result.
- Don't use ARKit for aiming. World tracking is visual-inertial and blinds itself against
  a dark sky; `CMDeviceMotion` with `.xTrueNorthZVertical` works in total darkness.
- Don't use gamma for the display curve. Use the asinh stretch in `Stacking.metal`.
- Don't commit `Starlapse.xcodeproj` — it is generated by `xcodegen`.

## Quality gate

1. Am I building bullshit? — re-read the request.
2. Is this code garbage? — would a senior accept it?
3. How do I make this amazing? — what insight is everyone missing?
