# Sky dataset: every shot measures the sky, and may contribute it

Asked 2026-10-19. Not a social network: no public profiles. Each phone, if its owner
allows it, contributes its measurements and the photo to a dataset we keep, for science
(light-pollution map like Globe at Night, meteor reports like IMO).

## Decisions
- Consent is asked once, after the first saved shot, defaulting to "Contribute"; one
  switch in Settings (SKY DATASET) turns it off; "Delete my contributions" erases
  everything sent from this phone (device id, as in analytics). PRIVACY.md + App Privacy.
- Location is rounded to 0.1° (~10 km) before it leaves the phone.
- Photos go to R2, measurements to D1, behind a Worker next to superduper-analytics.
  Nothing is shown publicly, so no UGC moderation surface in the app.

## Tracks
A. Sky meter (on device, no network)
 [x] A1 bright-star catalogue to V 6.5 (Yale BSC5, CDS V/50) as a generated Swift file
 [x] A2 SkyMeter: identify stars in the stack from pointing + FOV (offset vote, then
        StarAligner refine), zero point from catalogue magnitudes with extinction,
        background → mag/arcsec², NELM (Schaefer), Bortle class, stack limiting mag
 [x] A3 tests on a rendered sky with a known answer
 [x] A4 app: linear stack luminance (box-averaged, flux-preserving), pointing at
        capture, reading shown in review ("SKY 20.8 · BORTLE 4 · NELM 6.1")
B. Meteors
 [x] B1 streak endpoints → az/alt through the plate solution; time, duration
 [x] B2 shower association: great circle through the streak vs radiant positions
C. Contribution
 [x] C1 Worker + D1 + R2: POST /v1/observations (multipart: json + jpeg), DELETE by device
 [x] C2 app: consent, switch, upload queue (retry, Wi-Fi not required, small JPEG)
 [ ] C3 PRIVACY.md, README, ASC App Privacy (Photos, Precise→Coarse Location), review notes
D. Feed (later, asked 2026-10-19)
 [ ] D1 vertical full-screen feed of contributed shots, swipe like TikTok, opt-in to appear
 [ ] D2 a 3D globe with a point per shot, as a section of the feed
 [ ] D3 what App Review 1.2 then requires: report, block, filter, a contact, takedown
 Notes: B uses a plate solve of a watched frame (5 s in, then every 60 s until it holds);
 without one a meteor is kept as a clip but not placed on the sky.
