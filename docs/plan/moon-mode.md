# Moon mode

Asked 2026-10-27 after the 24–26 Oct India spike (likely Sharad Purnima, full moon 25–26 Oct):
"да сделай чтоб был режим или авто часть". Target: in the store before the 24 Nov supermoon.

## Why the app cannot shoot the Moon today

- Shortest shutter is clamped to the frame duration (`FormatFacts.shortestFrame`, ~1/30 s)
  and the slider stops at 0.1 s. A full Moon wants ~1/500–1/2000 s at base ISO: 4–6 stops over.
- Framing runs at 1/8 s and max ISO, the stack stretches with asinh: a white blob, twice.
- Star alignment needs six stars; the Moon drowns them, so nothing aligns.

## Shape

`StackMode.moon`, chosen from a "Moon" button on the main mode row (still capture underneath).
Short frames, disc-aligned, lucky-selected, developed without a stretch. Auto exposure meters
the disc continuously while framing. Auto part: when the Moon is inside the frame, the screen
offers Moon mode in one tap.

## Tasks

- [x] 1. Shutter shorter than the frame window: `FormatFacts.shortestShutter`,
      `FormatChoice.frameWindow(for:bounds:)`, ordering rule on windows. Tests.
- [x] 2. StackKit `MoonDisc.locate`: flood-filled bright blob around the peak, centroid,
      radius, peak, clipped fraction; rejects streetlights and empty skies. Tests.
- [x] 3. StackKit `MoonExposure.next`: meter the disc to a target peak, step down fast on
      clipping, ISO only when the shutter would pass 1/60 s. Tests.
- [x] 4. StackKit `LuckySelector` + disc sharpness score: keep frames at or above the running
      median after a warm-up. Tests.
- [x] 5. `StackMode.moon` in settings, plan, presets: fixed frame count, framing keeps the
      Moon exposure, neutral tone. Tests.
- [x] 6. `StackEngine`: disc tracking (translation to the reference disc), lucky rejection,
      disc metering published while framing.
- [x] 7. View model: entering Moon mode picks the narrowest lens and base ISO; auto-exposure
      loop while aiming; leaving restores the previous stack mode and settings.
- [x] 8. UI: Moon button, caption instead of the light presets, shutter slider down to the
      format's minimum in Moon mode, `.moon` left out of the sheet's stack picker.
- [x] 9. Auto part: Moon inside the frame (SkyKit position + attitude) → one-tap chip.
- [x] 10. l10n (9 languages), PRIVACY/README untouched (no new data), whats-new 1.2.0.
- [ ] 11. make test / test-app / lint / build, commit, TestFlight.

## Verified in the Simulator (stub sky with a Moon, `UITEST_MOON=1`)

- Meter converges from 1/1000 s to ~1/330 s and holds the disc at linear 0.71 for 12 s.
- Two bugs found that way and fixed: metering a frame still shot at the old exposure
  (overshoot; now waits 1 s after a change), and one saturated pixel on the disc reading as
  a blown Moon (the level is now the 99th percentile).
- A full capture: 100 kept, 100 dropped by the steadiness test, disc aligned through ±3 px
  of jitter, developed with the Moon tone.
- Not verified: a real Moon on a real iPhone (frame rate, telephoto format, seeing).
