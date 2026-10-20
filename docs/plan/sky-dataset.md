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

## Next (decided 2026-10-20)
E. Before the first real data
 [x] E1 send the raw measurement, not just the result: matched stars (V, B−V, flux,
        background, altitude) + solved pointing + `meterVersion`, so the whole dataset can
        be recomputed server-side when the calibration improves (colour term, extinction)
 [x] E2 CC BY 4.0, named in the consent text, PRIVACY.md and the site
F. Wow, in order of strength
 [ ] F1 public night-sky globe: one dot per reading coloured by Bortle, no photos (no
        moderation), works with ten users; the link for press, Reddit, astro forums
 [ ] F2 after a shot: "your sky 20.8, darker than 70% of readings in Spain"
 [ ] F3 share card "You caught an Orionid": the trail on a star chart, shower, time
 [ ] F4 two phones, one meteor: triangulate, show its orbit (needs density; later)
G. Science track (asked 2026-10-20; evidence for a US visa as well as science)
 [ ] G1 Research Notes of the AAS: method + first real readings vs a light-pollution map.
        Free, no peer review, any author, ≤1500 words + 1 figure. Needs data: after 1.1.0.
 [ ] G2 first dataset release with a DOI (Zenodo hook on fortunto2/starlapse-sky-data)
 [ ] G3 write to NOIRLab (Globe at Night): offer the readings for their database
 [ ] G4 NLnet Restack, deadline 2026-11-03 12:00 CET: anyone may apply, FOSS required;
        weak fit (open-internet infrastructure), short form; €5–50k (third-party figure)
 [ ] G5 Planetary Society STEP, next round ~2028: ≤$50k, international; fits "Defend
        Earth" if multi-phone meteor triangulation (F4) exists by then
 Not eligible (checked 2026-10-20): NSF SBIR (US ownership), NSF AAG (no unaffiliated
 individuals), NASA CSSFP (US institutions; excludes software-first projects),
 TÜBİTAK BiGG (no existing company stakes; via an accelerator; company in Turkey).
