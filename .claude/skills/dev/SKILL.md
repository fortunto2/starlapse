---
name: starlapse-dev
description: Dev workflow for Starlapse — build, test, run on device, and the hardware facts that constrain the design. Use when working on Starlapse features, camera control, stacking, sky math, or deploying to an iPhone. Do NOT use for other projects.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Starlapse dev workflow

Long-exposure astrophotography app for iPhone. Swift 6 strict concurrency, SwiftUI, Metal,
AVFoundation.

## Before changing anything in Services/

Three hardware facts drive every design decision. Violating one produces code that looks
right and fails in a field at 2am:

1. **iPhone aperture is fixed.** Choosing a "faster aperture" means choosing a lens.
2. **A single frame caps at ~1 s** (`activeFormat.maxExposureDuration`). Longer exposures
   are stacked. `CaptureSettings.totalLightSeconds` is intent; `frameCount` is reality.
3. **No background capture.** iOS force-stops `AVCaptureSession`. Never add
   `UIBackgroundModes` — the app dims the screen and holds `isIdleTimerDisabled` instead.

## Commands

```bash
make test          # 27 SPM tests, ~3s, no simulator
make integration   # CLI smoke test against tonight's sky
make build         # simulator compile check
make build-device  # device build (needs Apple ID in Xcode → Settings → Accounts)
make install       # build + install on the paired iPhone
make lint          # SwiftLint — keep this at zero
make gen           # regenerate Starlapse.xcodeproj from project.yml
```

`Starlapse.xcodeproj` is generated and gitignored. Edit `project.yml`.

## Where things live

| Change | File |
|---|---|
| Camera settings, locks, format choice | `Services/CaptureEngine.swift` |
| Stacking maths, tone curve | `Services/Shaders/Stacking.metal` |
| GPU accumulation, readback | `Services/FrameAccumulator.swift` |
| Per-frame orchestration | `Services/StackEngine.swift` |
| Star finding | `Sources/StackKit/StarDetector.swift` |
| Frame registration | `Sources/StackKit/StarAligner.swift` |
| Where to point the camera | `Sources/SkyKit/SkyDirector.swift` |
| Shower catalogue | `Sources/SkyKit/MeteorShower.swift` |
| Session state | `ViewModels/CaptureViewModel.swift` |

## Concurrency rules (Swift 6 strict)

- Capture-path types are `@unchecked Sendable` and confined to one serial queue. Keep them
  that way; do not add entry points that could be called from elsewhere.
- **Never send `MTLTexture` or `CVPixelBuffer` across an isolation boundary.** If a
  callback hands you a texture, consume it synchronously — the accumulator is cleared right
  after. `onFinished` carries no texture by design.
- View models are `@MainActor @Observable`. Use `@Observable`, never `ObservableObject`.

## Testing conventions

- Swift Testing (`@Test`, `#expect`), not XCTest.
- Domain modules import only Foundation/simd — that is what keeps tests device-free. If you
  need a platform import in `SkyKit` or `StackKit`, the code belongs in `Services/`.
- **Never write a raw `timeIntervalSince1970` in a test.** Use `Self.utc(y, m, d, h)`. The
  first draft had four such constants and three pointed at the wrong day — the tests failed
  and the maths was fine.
- Anchor sky tests to external facts (the 2026-08-12 eclipse is a new moon; Polaris altitude
  equals latitude), not to the implementation's own output.
- Test alignment against synthetic star fields rotated by a known angle.

## Adding a meteor shower

Append to `MeteorShower.catalog` with the IAU code, J2000 radiant, ZHR, entry velocity and
the activity window. Windows that wrap New Year are handled — see the Quadrantids and the
`isActive(on:)` comparison.

## Device deploy

Needs an Apple ID signed into Xcode (Settings → Accounts), and `TEAM` / `DEVICE` set in
`Makefile.local` (gitignored — copy `Makefile.local.example`). Without a team,
`make build-device` fails on provisioning while `make build` still works.

```bash
make device      # list paired devices, copy the identifier
make install
```

Use the device *identifier*, not its name — device names often contain a typographic
apostrophe that no shell quoting survives.

## Field checklist

A build is not verified until it has seen sky. Check: stars round (not streaked) after a
5-minute stack; star count and residual shown while tracking; ISO/shutter unchanged at the
end of a session; the aiming arrow agrees with a recognisable constellation.
