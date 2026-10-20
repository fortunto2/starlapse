---
title: Privacy Policy
permalink: /privacy/
---

# Privacy Policy — Starlapse

**Last updated: 20 October 2026**

Starlapse has no account. Your photographs, your location and the direction you point the
phone stay on it, unless you choose to join the sky dataset, and then only in the coarsened
form described below. Every network request the app makes is listed here, and each one
except the purchase can be switched off.

That is unusual enough for a camera app that the rest of this document exists mainly to be
specific about it.

## What the app uses, and why

**Camera.** To photograph the night sky. Frames are combined on your device — that is the
entire product — and the result is written to your photo library only when you tap Save.
Nothing is uploaded unless you join the sky dataset (below), and nothing is kept outside your
photo library and the app's temporary folder.

**Location, while the app is open.** Used to compute where things are in the sky above you:
which meteor showers are active, where their radiants sit, where the Moon is, and therefore
where to point the camera. The calculation runs entirely on your device using published
astronomical formulas. Your position is not sent anywhere, except rounded to 0.1° (about
10 km) with a sky dataset contribution if you join it, and it is not stored on disk. Deny it and everything still works except the aiming
overlay.

**Motion sensors.** The gyroscope, accelerometer and magnetometer tell the app which way the
camera is aimed, so the sky overlay lines up with what you see. The raw readings never leave
the device; a sky dataset contribution carries only the direction the photo was taken in.

**Photo library, add-only.** Used to save your finished photographs and videos. The app
requests add-only access, which means it can put pictures in your library but cannot read,
browse or scan what is already there.

**Notifications, if you allow them.** Reminders on the evening of a good meteor night
from where you are. They are worked out on your device from the same forecast the app shows
and scheduled with iOS as local notifications: nothing is sent to us or anyone else to make
them, and no push service is involved. Switch them off in Settings › SHOWER ALERTS, or in the
iOS Settings app.

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

**The sky dataset, if you join it.** Every stack measures how dark the sky is from the
stars in it. If you choose to contribute (the app asks once, after your first saved photo,
and the answer can be changed in Settings › SKY DATASET), each saved stack sends: that sky
reading (brightness in magnitudes per square arcsecond, the naked-eye limit, the Bortle
class, the direction the camera pointed in whole degrees, and the stars it was measured
from: each one's catalogue magnitude and colour, its measured brightness and the sky around
it, and its height in whole degrees), the camera
settings (lens, ISO, shutter, frame count, field of view, iPhone model), a 2048-pixel JPEG
of the photo, the time it was taken, your location rounded to 0.1° (about 10 km), the app
version and a random contributor identifier made on this phone (not the usage counter's,
not your Apple ID; it is kept in the iOS Keychain so a later delete still reaches it after
a reinstall). Directions are rounded to whole degrees on purpose: the height of known stars
at a known time pins down where on Earth they were seen, and whole degrees keep that to
about 100 km, coarser than the rounded location itself. A detector session sends the meteors it placed on the sky (time,
start and end direction, length, the shower they belong to), without the video clips.

It goes to our own server at api.starlapse.app, and from there into an open scientific
dataset, published under CC BY 4.0 (on Zenodo, Hugging Face and GitHub) so anyone can study
light pollution and meteor activity with it. The published copy carries no contributor
identifier at all, only a one-way code that groups one phone's readings together; nothing in
it names you. **Delete everything I contributed** in Settings › SKY DATASET
erases every reading and photo sent from this phone, on the server, at once, and keeps them
out of every later release. Copies already downloaded from an earlier release cannot be
recalled; that is what open data means, and why the location in it is coarse.

**Crash reports** are kept on the phone and sent only when you tap Send in the controls
panel. They contain the camera's error message and the code path, never a photo or a
location.

## What Starlapse does not do

- No accounts, sign-in, or user identifiers tied to you
- No sky dataset contribution without your yes
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

Starlapse is not directed at children. It collects nothing that identifies a person; the
sky dataset, if joined, holds coarse locations and sky photos under a random identifier.

## Changes

If this policy ever changes, the updated version will appear at this address with a new date
at the top. The full revision history is public in
[the repository](https://github.com/fortunto2/starlapse/commits/main/PRIVACY.md) — you can
see exactly what changed and when.

## Contact

Questions: **info@superduperai.co**

Source code: [github.com/fortunto2/starlapse](https://github.com/fortunto2/starlapse) — MIT
licensed, so the claims above are verifiable rather than merely asserted.
