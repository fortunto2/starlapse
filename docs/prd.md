# PRD — Starlapse

**Status:** v1 in build · **Created:** 2026-08-13 · **Stack:** ios-swift

## Problem

Shooting the night sky on an iPhone fails in three specific ways, and none of them are the
user's fault:

1. **Manual controls do not hold.** Third-party camera apps expose ISO and shutter sliders,
   then let the system drift them back. Autofocus hunts against a black sky and settles
   nowhere. Auto white balance renders the sky orange under any sodium streetlight.
2. **"Long exposure" is a lie on this hardware.** People expect 10 s – 1 h exposures from
   DSLR practice. `AVCaptureDevice.activeFormat.maxExposureDuration` caps a single frame at
   about one second, and Apple's 30 s Night mode is private API. Apps that advertise long
   exposures are stacking frames without explaining it, so users cannot reason about the
   result.
3. **Nobody knows where to point.** During the 2026 Perseids the trigger for this project
   was simply not knowing which way to face. Sky maps exist, but none connect "the radiant
   is there" to "so point the camera *here*", which is not the same direction.

## Users

Primary: one photographer with an iPhone 14 Pro Max, a tripod, and clear skies over
southern Turkey. Secondary: anyone who has tried to photograph a meteor shower on a phone
and got a black rectangle.

## Solution

A capture app built around what the hardware actually does, stated plainly rather than
hidden:

- Lock every camera parameter with `setExposureModeCustom` / `setFocusModeLocked` /
  `setWhiteBalanceModeLocked`, and disable every automatic subsystem that would undo them.
- Treat stacking as the feature, not the workaround. The user asks for "10 minutes of
  light"; the app shows "600 × 1.00s" and the resulting √N noise gain.
- Align on the stars so long stacks stay sharp, or deliberately do not, for trails.
- Compute where to aim from ephemerides — 40° off the radiant, away from the Moon, at a
  height a tripod can hold.

## Scope — v1

| Feature | Notes |
|---|---|
| Manual locked camera | ISO, frame exposure, focus, WB, lens selection |
| Stacking, 10 s – 1 h | average / lighten / star-aligned average |
| Star alignment | sub-pixel centroids, closed-form rotation, hot-pixel rejection |
| Night time-lapse | each output frame is a stack; shows resulting video length up front |
| asinh tone curve | stretch, black point, saturation |
| Aiming overlay | radiants, Moon, bright stars, turn-by-turn arrow |
| Night UI | red on black, screen dimmed, idle timer disabled |
| CLI | `starlapse-sky tonight/showers/moon` |

## Out of scope — v1

- ProRAW / DNG capture and export (stacking from RAW is a v2 question)
- Dark-frame and flat-field calibration
- Plate solving against a real star catalogue
- Light-pollution maps and cloud forecasts
- Sharing, editing, cloud anything

## Non-negotiables

- **Never silently change a locked setting.** The entire premise.
- **Never claim an exposure the sensor did not take.** Always show the frame arithmetic.
- **Never promise background capture.** iOS does not allow it; say so in the UI.

## Success criteria

1. A one-hour stack of the Perseids comes out with round stars, not streaks.
2. The aiming arrow puts a first-time user on a shootable patch of sky in under a minute.
3. ISO and shutter read the same at the end of an hour-long session as at the start.
4. The time-lapse screen tells you it will be 2.5 seconds long *before* you drive out.

## Risks

| Risk | Mitigation |
|---|---|
| Alignment fails on sparse or cloudy fields | Drop untrusted frames; show live star count and residual |
| Thermal throttling over an hour | 1 fps pipeline, single dispatch per frame, dimmed screen |
| Magnetometer heading error near metal/cars | Show bright stars as a visual cross-check |
| Hot pixels anchoring alignment to the sensor | Shape discriminator in `StarDetector` |
