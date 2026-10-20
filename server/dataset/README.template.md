---
license: cc-by-4.0
pretty_name: Starlapse sky dataset
tags: [astronomy, light-pollution, sky-quality, meteors, citizen-science]
---

# Starlapse sky dataset, release {{version}}

Night-sky readings contributed by people photographing the sky with
[Starlapse](https://starlapse.app), an iPhone long-exposure camera, who chose to share them.
{{count}} observations, {{photos}} photos, {{meteors}} meteors in this release.

## How a reading is made

Each stack (hundreds of ~1 s frames, aligned on the stars) is matched against the Yale Bright
Star Catalogue. Every identified star of known V magnitude is compared with the sky in a ring
around it; exposure, ISO, vignetting and lens throughput cancel because star and sky went
through the same pixels. The median gives sky surface brightness in V mag/arcsec², the
quantity a Sky Quality Meter reports. Extinction is corrected at 0.2 mag per airmass (Kasten
and Young). No colour term yet: a phone's luminance is not Johnson V, expect ±0.2 mag
systematics. `stars.csv` holds the raw per-star measurements so readings can be recomputed with
a better calibration; `meter_version` says which algorithm produced each row.

## Files

- `observations.csv`: one row per contribution. `kind` is `stack` (a sky reading) or
  `meteors` (a detector session). `contributor` is a stable one-way code per phone.
  `latitude`/`longitude` are rounded to 0.1° (~10 km); `altitude`/`azimuth` of the frame
  centre to whole degrees. `camera` is JSON (lens, ISO, shutter, frames, field of view, model).
- `stars.csv`: per observation, the stars used: catalogue `magnitude` and `colorIndex` (B−V),
  measured `flux` and `background` (linear, per pixel), `pixelArea` (arcsec²), `altitude`
  (whole degrees).
- `meteors.csv`: per detector session, each meteor placed on the sky: time, start/end az/alt,
  length (degrees), associated shower (IMO code, or empty for sporadic), relative flux.
- `photos/<id>.jpg`: the stacked photo, 2048 px on the long side.

## Caveats

Phones are uncalibrated instruments; treat single readings with care and aggregates with
less. Clouds and the Moon brighten readings; sky brightness depends on altitude (recorded).
Contributors can delete their data, which removes it from all later releases.

## Citation

Starlapse sky dataset, Starlapse contributors, release {{version}}. CC BY 4.0.
Source and method: https://github.com/fortunto2/starlapse
