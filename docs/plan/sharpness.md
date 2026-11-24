# Sharpness: why contributed photos are smeared, and what to change

Measured 24 Nov 2026 on the 85 dataset photos (1.1.0–1.2.1), with their camera metadata.

## What the data says

- **Short, handheld sessions.** 38 of 85 photos are stacks of 3 frames or fewer; 14 are 0–1
  frames. A 1 s frame held in the hand is a smear: light loops (070/071, ISO 12768), rotated
  foreground (066/067, 082–085), ghost edges (016). Stacking cannot fix motion inside a frame.
- **No warning while it happens.** "Hold still, the tripod must not move" appears only during
  the focus sweep. During capture nothing says the phone is moving, and the shutter press
  itself shakes the first frame.
- **Focus defaults to the end stop.** `focusPosition = 1.0`; the sharpest point sits slightly
  inside it (see `CaptureViewModel+Focus.swift`). The star-size sweep exists but only runs when
  asked. Blobs instead of points in 017/018/057.
- **Saving 0-frame results.** `frames = 0` photos were saved and uploaded: the review offers a
  result that holds no stacked frame.

## Plan (1.2.3), each with the number it should move

1. **Motion gate.** `CMDeviceMotion` rotation rate during capture; above ~0.02 rad/s, a red
   "Phone is moving: use a tripod or lean it on something" line, and frames shot while moving
   are dropped like failed alignments. Moves: share of `capture_finished` with `frames ≤ 3`
   (today ~45% of contributed stills).
2. **Start delay.** 2 s countdown after the shutter press (off in settings), so the press does
   not shake frame one.
3. **Focus before the first stack.** Run the star-size sweep automatically once per night
   when stars are detected in framing; keep the result per lens. Moves: FWHM of stars in
   contributions (StarDetector spread), measured with `starlapse-stack detect`.
4. **No result from zero frames.** Review with `framesStacked == 0` says so instead of
   offering Save.

Check after release: `capture_finished` metrics `frames` and `minutes` by version.
