---
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy — Starlapse

**Last updated: 6 October 2026**

Starlapse has no account and no server of its own. Your photographs, your location and the
direction you point the phone never leave it. The app makes two kinds of network request,
both listed below, and one of them you can switch off.

That is unusual enough for a camera app that the rest of this document exists mainly to be
specific about it.

## What the app uses, and why

**Camera.** To photograph the night sky. Frames are combined on your device — that is the
entire product — and the result is written to your photo library only when you tap Save.
Nothing is uploaded, and nothing is kept outside your photo library and the app's temporary
folder.

**Location, while the app is open.** Used to compute where things are in the sky above you:
which meteor showers are active, where their radiants sit, where the Moon is, and therefore
where to point the camera. The calculation runs entirely on your device using published
astronomical formulas. Your position is never sent anywhere, never stored on disk, and is
discarded when the app closes. Deny it and everything still works except the aiming
overlay.

**Motion sensors.** The gyroscope, accelerometer and magnetometer tell the app which way the
camera is aimed, so the sky overlay lines up with what you see. This data is used for
display only and never leaves the device.

**Photo library, add-only.** Used to save your finished photographs and videos. The app
requests add-only access, which means it can put pictures in your library but cannot read,
browse or scan what is already there.

## What the app sends

**Purchases.** Starlapse Pro is bought through Apple's App Store. The request goes to Apple
and is governed by Apple's privacy policy; the app sees only whether this phone owns Pro.

**A usage counter.** Five events, so we know whether anyone opens the app and comes back:
app opened, capture started (with the mode: still, time-lapse or detector), capture saved
(with the frame count), Pro page shown, Pro bought. They go to our own server at
analytics.superduperai.co, not to a third party. Each event carries the app version, the
platform and a random identifier generated on this phone when the counter first runs. That
identifier is not your Apple ID, not the advertising identifier, not shared between apps,
and is deleted with the app. No photos, no location, no heading, no name.

You can switch the counter off in the controls panel, under **Usage counter**. Off means
nothing is sent, including events already waiting to be sent.

**Crash reports** are kept on the phone and sent only when you tap Send in the controls
panel. They contain the camera's error message and the code path, never a photo or a
location.

## What Starlapse does not do

- No accounts, sign-in, or user identifiers tied to you
- No advertising SDKs, no third-party analytics
- No tracking across apps or websites
- No selling or sharing of data
- No reading of your existing photos

## Where your captures live

Finished photographs and time-lapses go to your photo library, under your control, and are
governed from that point by Apple's Photos privacy settings rather than by this app.

Event clips from detector mode are written to the app's temporary folder first, so you can
review them before deciding. Anything you discard is deleted; anything you keep is copied
to your photo library. Uninstalling the app removes everything left in its temporary
folder.

## Children

Starlapse is not directed at children and collects no personal information from anyone,
regardless of age.

## Changes

If this policy ever changes, the updated version will appear at this address with a new date
at the top. The full revision history is public in
[the repository](https://github.com/fortunto2/starlapse/commits/main/PRIVACY.md) — you can
see exactly what changed and when.

## Contact

Questions: **info@superduperai.co**

Source code: [github.com/fortunto2/starlapse](https://github.com/fortunto2/starlapse) — MIT
licensed, so the claims above are verifiable rather than merely asserted.
