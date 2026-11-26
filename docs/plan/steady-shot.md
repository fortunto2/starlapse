# 1.2.3: a good picture by default, even from unsteady hands

Measured 24 Nov 2026, 30 days of events (465 people launched, 279 started a capture):

- Still/stars, the main path: default Auto = 5 min (300 frames), but the median person saves
  after **51 s**, median **8 frames**; 74 of 263 saves have 3 frames or fewer. A quarter of
  starts are abandoned and restarted without a save.
- Dataset photos (85): handheld 1 s frames are smears; stacking cannot fix blur inside a frame.
- Detector: 93 starts, 0 `capture_saved` — clip saves were never counted.

## Tasks

- [x] ShakeLog: gyro samples kept 30 Hz always (attitude publishes at its own cadence), a
      lock-protected ring the capture queue reads. `Steadiness` (pure) classifies a window.
- [x] Frame gate: a frame whose exposure window saw the phone move is dropped like a failed
      alignment, counted as `framesMoved`.
- [x] Handheld shutter (26.11, replaces the wait): the press reads the gyro; a shaking
      phone gets `Steadiness.handheldExposure` frames (≈1/15 s at 0.03 rad/s) with ISO
      raised to match, and Auto runs 30 s. Hint under the light picker before the press.
- [ ] Shutter delay `AUTO` by default: wait until the phone has been steady for 1 s (cap 10 s),
      then start. Cycle AUTO → 3 s → 10 s → OFF; remembered.
- [x] Capture screen: steadiness hint before the press; during capture a red line when frames
      are being dropped for motion; time left and "stop any time".
- [ ] Auto light for pinpoint stars 5 min → 2 min.
- [ ] Review with 0 frames offers no Save.
- [ ] Detector clip saves → `capture_saved{kind:clip}`; `capture_finished` gets metric `moved`.
- [ ] l10n for new strings, tests, simulator check, release notes.

Moves: share of still saves with frames ≤ 3 (today 28%), starts per save (today 1071/431).

26.11: taken over from session 0f6ab06e (idle since 24.11). Not field-tested: the gyro
thresholds (0.006 / 0.03 rad/s) and the PTS/motion clock match are still assumptions.
