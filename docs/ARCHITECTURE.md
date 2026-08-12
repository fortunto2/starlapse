# Architecture

## Dependency rule

```
SkyKit / StackKit  ←  Services  ←  ViewModels  ←  Views
   (domain)           (adapters)     (state)       (UI)
```

Dependencies point inward. `SkyKit` and `StackKit` import nothing but `Foundation` and
`simd` — no AVFoundation, no Metal, no SwiftUI, no CoreLocation. That constraint is what
makes 27 tests run in three seconds on a Mac with no simulator and no device, and it is
worth defending: if a domain type ever needs a platform import, the type is in the wrong
module.

## Modules

| Module | Owns | Never touches |
|---|---|---|
| `SkyKit` | Time scales, coordinate transforms, meteor showers, Sun/Moon, aiming advice | Anything platform |
| `StackKit` | Star detection, sub-pixel centroids, frame registration | Anything platform |
| `SkyKitCLI` | `starlapse-sky` — CLI-first access to the domain | UI, camera |
| `Services` | AVFoundation, Metal, CoreMotion, AVAssetWriter, Photos | SwiftUI |
| `ViewModels` | Session state, orchestration, saving | Metal internals |
| `Views` | SwiftUI, night theme, overlay projection | Capture internals |

## Data flow

```
AVCaptureVideoDataOutput
   └─ capture queue ─────────────────────────────────────────────┐
        CaptureEngine → SensorFrame                              │
          └→ StackEngine.consume                                 │
               ├→ FrameAccumulator.readLuminance  (GPU → CPU)    │  all on one
               ├→ StarDetector.detect             (CPU)          │  serial queue
               ├→ StarAligner.align               (CPU)          │
               ├→ FrameAccumulator.add            (GPU)          │
               └→ on segment: resolve → TimelapseWriter.append   │
   └──────────────────────────────────────────────────────────────┘
                        ↓ StackProgress (Sendable)
                   @MainActor CaptureViewModel → Views
```

One queue owns the whole capture path. Only `StackProgress` — a plain `Sendable` struct —
crosses to the main actor. GPU textures never do.

## Why some things are not what you would expect

**`@unchecked Sendable` instead of actors.** `AVCaptureSession`, `AVCaptureDevice` and
Metal command queues are queue-confined by design and predate actors. An actor wrapper
would suspend on every blocking `startRunning()` and buy no safety that the queue does not
already provide. The discipline is documented on each type and enforced by keeping the
entry points few.

**`CMDeviceMotion`, not ARKit.** ARKit world tracking is visual-inertial: it needs the
camera to see textured surfaces. Aimed at a dark sky it degrades to
`.limited(.insufficientFeatures)` within seconds and heading drifts. `.xTrueNorthZVertical`
device motion uses gyroscope, accelerometer and magnetometer only — it works in total
darkness, costs less battery, and does not compete with the capture session for the camera.

**Frame-to-frame alignment, not frame-to-reference.** Between consecutive one-second frames
the sky moves about 15 arcseconds, so nearest-neighbour matching converges immediately and
never has to solve the hard rotation-invariant matching problem. Transforms compose across
the session; a test chains 60 of them and checks the total against ground truth.

**Float32 accumulation.** Eight-bit frames summed into an 8-bit buffer clip within a few
frames and quantise exactly the shadow detail the app exists to recover.

**asinh, not gamma.** Nearly linear near zero and logarithmic above, so faint nebulosity
lifts out of the noise while bright stars keep their cores and colour instead of clipping
to flat white discs. This is what professional astronomical imaging uses.

## Module size limits

Per dev-principles: function > 150 lines → split; module > 1000 lines → split. Current
largest source file is under 400 lines.
