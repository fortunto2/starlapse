# Quality Score

Grades per domain, refreshed when a domain changes. Anything at C or below is either fixed
or has a written reason to stay.

| Domain | Grade | Basis |
|---|---|---|
| Sky math (`SkyKit`) | A | Anchored to external facts (eclipse date, synodic month, Polaris) rather than to itself |
| Planets (`Planets.swift`) | A | Checked against orbital mechanics: Kepler inverts, inner planets stay near the Sun, periods follow the third law |
| Star detection & alignment (`StackKit`) | A | Synthetic fields with known rotation; sub-pixel accuracy and hot-pixel rejection both proven |
| Metal stacking (`FrameAccumulator`) | B | Double-buffered after a real crash; shaders reviewed, no GPU test harness |
| Camera control (`CaptureEngine`) | B | Runs on device, but no test can assert ISO stayed locked for an hour |
| Session orchestration (`CaptureViewModel`) | B | Live preview and crash paths fixed after field test; storage-full path still unexercised |
| Aiming overlay (`SkyOverlayView`) | C | Projection approximate by design; not yet verified against real stars |
| Time-lapse (`TimelapseWriter`) | C | Never run to completion. One real hour is the only way to know |

## Field test — 2026-08-13, first night

Three failures, all above the domain layer, none catchable by the 34 tests:

| Symptom | Cause | Fix |
|---|---|---|
| Camera appeared dead, black screen | Engine dropped frames until a session started; no live state existed | `Activity.live` renders each frame as it arrives |
| Crash at end of capture | Main actor rendered via the accumulator while the capture queue wrote to it — one command queue, one texture | Two display textures, push-only delivery, `RenderedImage` for saving |
| Text unreadable outdoors | `dim` at (0.42, 0.09, 0.07), brightness 0.05 | White default, red behind a toggle, brightness 0.2 |

Also found: `MTLBlitCommandEncoder` does not scale, so the preview showed the corner of the
sensor frame. Presentation now goes through a render pass.

## Resolved after the cleanup pass

Both deferred findings turned out to be worth doing immediately — the second one because a
third crash arrived while it was still on the list.

**`Activity.live` → `SegmentPlan`.** Framing is now data, not a branch: one frame per
segment, no alignment, no segment count. `consume()` has a single path. The unexpected
payoff was a rule that fell out of it — *the first frame of a segment replaces the buffer
instead of adding to it* — which removed every explicit `clear()` in the codebase along with
the whole class of "stacked on top of the previous thing" bugs, and stopped a ~200 MB
write of zeros per framing frame.

**Crash on the stop button.** `cancel()` ran `finish()` — Metal resolve plus a full-frame
readback — directly on the main thread from a button tap, while the capture queue was
mid-frame. The same race as the first crash, entered from the other side. The fix is the one
the altitude review pointed at: the pipeline queue is now an object (`CaptureQueue`) shared
by `CaptureEngine` and `StackEngine`, so "run this on the pipeline" is something you write
rather than something you remember. `cancel()` hops onto it.

**`PreviewFrame` ownership is now structural.** Textures come from a `TexturePool` with
explicit `acquire`/`release`; `PreviewFrame` carries its return ticket. The view releases
from the command buffer's completion handler — when the GPU has actually finished sampling,
not when SwiftUI got around to a redraw. If the display holds every texture, `resolve()`
returns nil and the preview frame is skipped: the producer never blocks, because the queue
it would block is the one carrying the photons.

## Deferred from the detector cleanup

Both are right, both are bigger than a cleanup pass, and neither is load-bearing today:

1. **`SegmentPlan` should be an enum with per-case payloads.** It currently has three
   overlapping descriptors — `kind`, `segments`, `detector` — so illegal states are
   representable (`.framing` carrying a detector, `.watching` with a segment count), and on
   the watching case five of seven fields are dead. `enum { framing, capturing(Recipe),
   watching(DetectorSettings) }` makes them unrepresentable, and would delete the test that
   exists purely to defend the current representation.
2. **One `ReviewSubject` instead of three signals.** "Which result am I looking at" is
   currently re-derived from `mode.isDetector`, `reviewVideoURL != nil` and
   `mode.isTimelapse` across eight sites. `enterReview()` knows the answer exactly once;
   it should publish `enum { stack, video(URL), events([RecordedEvent]) }` and let every
   caller switch on that.

## Known gaps

1. **Time-lapse never run to completion.** Ordering is correct by construction; an hour-long
   run has still not happened.
2. **Alignment unproven on real sky.** Synthetic fields say it works. Whether a real frame
   yields enough stars to track is unknown.
3. **Magnetometer accuracy unmeasured.** Heading error near tripod metal or a car is
   untested; planet and bright-star markers are the intended cross-check.
4. **Thermals unmeasured** over a full hour.

## Test inventory

```
SkyKitTests    26  time, coordinates, Sun/Moon, planets, showers, aiming
StackKitTests   8  detection, centroids, hot pixels, alignment, transform algebra, drift
```

Run: `make test` (~3 s, no simulator).
