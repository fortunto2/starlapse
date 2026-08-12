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

## Deferred from the cleanup pass

Two findings were real but larger than a cleanup. Both are safety-by-convention where
safety-by-construction is available:

1. **`PreviewFrame`'s borrow is prose, not structure.** The type documents "the view reads
   this while the capture queue writes elsewhere", then the handler stores the bare texture
   indefinitely one line after the boundary. Double-buffering bounds the producer at the
   instant of hand-off, not the consumer's hold time. The structural fixes are a scoped
   accessor (`withTexture { }`, or `~Copyable`) so the texture cannot be stored, or the
   standard Metal N-buffering handshake — a semaphore signalled from the consumer's
   `addCompletedHandler`, which also turns the buffer count into real backpressure.
2. **`Activity.live` is a branch, not a policy.** Framing is a degenerate session: one frame
   per segment, no alignment, no terminal condition. Modelled as `SegmentPlan`, `consume()`
   collapses to a single path and the live branch stops being able to drift from the session
   one — it already had, hardcoding `.smooth` and skipping `report()`.

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
