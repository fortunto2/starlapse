# Daylight: metered framing and a one-frame day photo

Asked 2026-10-30 after the first Moon-mode test on the phone: "днем когда светло чет белый
фон засветка... и авто режим если стоит наверно надо не ждать там условно чегото долго... и
может просто дневную простую фотку делать".

## Why it happens

Framing runs at a fixed 1/8 s and the sensor's top ISO, chosen so a dark horizon shows at
night. In daylight that is 12–13 stops over: a white screen. And Auto picks minutes of light
for whatever stack mode is set, whatever the sky.

## Shape

- A framing meter runs while aiming in every mode: scene median to linear 0.18, never more
  light than the night framing. At night it asks for more than it may give, so the night
  framing stays exactly as it was.
- Daylight = the metered framing needs at most 1/100 s at ISO 100 (EV ≈ 10.6); leaves at
  twice that, so it does not flicker at dusk. Framing is then developed with a day curve.
- Auto + daylight + Exposure mode = a day photo: one frame at the metered exposure, day curve,
  no sky measurement, no dataset contribution.

## Tasks

- [x] 1. StackKit: `SceneLevel` (median, clipped share) and `ExposureMeter` (Moon and scene
      targets; a mostly white frame steps five stops, not three). Tests.
- [x] 2. Framing meter in the view model; `forFraming(metered:)`; Moon metering folded in.
- [x] 3. Daylight flag with hysteresis; framing tone follows it (`StackEngine.setFramingTone`).
- [x] 4. Day photo: Auto + daylight → one frame, `.day` tone, session tone kept for review.
- [x] 5. UI: LightPicker caption, exposure readout. l10n.
- [x] 6. Stub sky that answers exposure in daylight (`UITEST_DAY=1`); verify in the Simulator.
- [x] 7. Tests, lint, commit, build to the phone.

## Verified in the Simulator (`UITEST_SKY=1 UITEST_DAY=1`)

- From the white night framing to a metered preview in three readings (1/8 s ISO 12288 →
  1/30 s ISO 180 → 1/2346 s → 1/1038 s), median held at 0.174 against 0.18.
- Auto in daylight: caption "Auto: daylight, so one photo", one frame, review on the day curve.
- Night stub unchanged: framing stays at the night exposure, Auto still 5 min for stars.
- Found on the way: the sky overlay darkened the preview by ~40%, at night too, since the
  first build. Bisected by part: any full-screen SwiftUI view over the MTKView (the horizon
  line alone) did it. The CAMetalLayer had no colour space, so it was shown as is when
  uncovered and colour-matched when composited. Set to sRGB, both paths agree; the overlay
  stays on in daylight, stars over a day sky being the point. The stub's per-pixel `pow` took longer
  than a frame and starved the capture queue — encoded per row now.
