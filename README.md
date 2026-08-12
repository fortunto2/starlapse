# Starlapse

Long-exposure astrophotography for iPhone. Manual camera control that actually holds,
frame stacking for exposures from 10 seconds to an hour, star-aligned or trailed, night
time-lapse, and an aiming overlay that works in the dark.

## Why

Phone camera apps advertise manual control and then quietly drift back to automatic — ISO
creeps, autofocus hunts in the dark and lands on nothing, white balance turns the sky
orange. And they promise "long exposure" that the hardware cannot deliver: an iPhone
sensor caps a single frame at about one second.

Starlapse does the honest version. Every setting is locked and stays locked. Exposures
longer than a second are built by stacking hundreds of frames, which is not a compromise —
it is better. Noise falls as √N, and the same night's frames can be rendered as pinpoint
stars or as star trails after the fact.

## What it does

- **Manual, locked** — ISO, frame exposure, focus (infinity, held), white balance, lens.
  Nothing drifts once a session starts.
- **Stacking** — 10 s to 1 h of total light. Three renderings:
  - *Pinpoint stars* — frames aligned on the stars, then averaged
  - *Star trails* — brightest pixel wins, the sky draws arcs
  - *Clean landscape* — averaged as shot
- **Star alignment** — sub-pixel centroids, closed-form rotation fit, hot pixels rejected
- **Night time-lapse** — every output frame is its own stack ("holy grail" night lapse)
- **Aiming overlay** — meteor shower radiants, the Moon, bright stars, and where to
  actually point (40° off the radiant, away from the Moon, at a workable height)
- **asinh stretch** — the curve professional astronomical imaging uses, not gamma
- **Red on black, dimmed** — keeps 20–30 minutes of dark adaptation intact

## Requirements

- iPhone with iOS 18+ (developed against a 14 Pro Max and a 17 Pro)
- Xcode 26, XcodeGen (`brew install xcodegen`)
- A tripod. Non-negotiable — an hour of stacking on a handheld phone is an hour of nothing.

## Build

```bash
make test          # 27 domain tests, ~3s, no simulator needed
make build         # simulator build
make install       # build and install on a paired iPhone
```

## The CLI

The sky math runs standalone, which is how it gets tested and how you plan a night without
opening the app:

```bash
swift run starlapse-sky tonight --lat 36.545 --lon 32.0
```

```
  CONDITIONS  ████████████████████  100%
  Astronomical night, no Moon — best conditions

  ACTIVE SHOWERS
    Perseids                    44.1/h   radiant: NE 39° az, 33° up

  POINT THE CAMERA
    E 88° az, 53° up
    Perseids — 40° off the radiant — that is where the trails are longest

  Better later: 2026-08-13T23:50:00Z → 59.3/h
```

Also `starlapse-sky showers` and `starlapse-sky moon --lat … --lon …`.

## Honest limits

- **No background capture.** iOS force-stops the camera when an app backgrounds; no app
  can work around it. Starlapse keeps the screen on and dims it to near-black instead.
- **Aperture is fixed.** It is a property of the lens, not a setting. The app shows the
  f-number and how many stops each lens gives up, and lets you pick — that is all anyone
  can do on this hardware.
- **A frame is ~1 second.** Longer exposures are stacked. The UI always shows the
  translation: "10 min of light = 600 × 1.00s".

## Licence

Private project.
