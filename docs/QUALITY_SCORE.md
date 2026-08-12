# Quality Score

Grades per domain, refreshed when a domain changes. Anything at C or below is either fixed
or has a written reason to stay.

| Domain | Grade | Basis |
|---|---|---|
| Sky math (`SkyKit`) | A | 19 tests, anchored to external facts (eclipse date, synodic month, Polaris) rather than to itself |
| Star detection & alignment (`StackKit`) | A | 8 tests on synthetic fields with known rotation; sub-pixel accuracy and hot-pixel rejection both proven |
| Camera control (`CaptureEngine`) | B | Correct and complete, but only verifiable on a device — no test can assert that ISO stayed locked for an hour |
| Metal stacking (`FrameAccumulator`) | B | Shaders are simple and reviewed; no GPU-level test harness yet |
| Time-lapse (`TimelapseWriter`) | C | Untested end to end. Needs one real hour-long run before it can be trusted |
| Aiming overlay (`SkyOverlayView`) | C | Projection is approximate by design; needs field verification against real stars |
| Session orchestration (`CaptureViewModel`) | B | Straightforward, but the failure paths (tracking lost mid-session, storage full) are unexercised |

## Known gaps

1. **No device test yet.** Everything above the domain layer is verified by compilation and
   reasoning, not by photons. The first clear night is the real test.
2. **Time-lapse never run to completion.** The segment/clear/append ordering is correct by
   construction and by contract comment, but an hour-long run has not happened.
3. **Magnetometer accuracy unmeasured.** Heading error near cars or tripod metal is unknown;
   bright-star markers are the intended cross-check but have not been checked.
4. **Thermals unmeasured.** An hour at 1 fps with the GPU active should be fine. Should.

## Test inventory

```
SkyKitTests    19  time, coordinates, Sun/Moon, showers, aiming
StackKitTests   8  detection, centroids, hot pixels, alignment, transform algebra, drift
```

Run: `make test` (~3 s, no simulator).
