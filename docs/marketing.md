# Marketing: short vertical video, founder-led first

Written 2026-10-20. Source: a UGC agency talk at the Vizard × Alibaba event, LA Tech Week,
15 Oct 2026 (transcript in the USA trip folder, `la_venice_1015-out/day.txt`, clip 0040; shorts
`billion`, `genz`, `moat`). Numbers about Starlapse come from superduper-analytics.

## Where we are

Three weeks of events, 2026-09-29 to 2026-10-20: 171 launches, 187 captures started, 85
saved, 30 paywall views, **2 Pro purchases** (≈7 % of paywall views). Pro is $4.99 once,
about $3.50 after Apple. The app is new and the funnel works; what it lacks is people.

## What the agency said, and which half applies

Their pitch: creators are the channel for apps in 2026. One client, since March: 308,000
creator videos, 1.4 billion views, under $3M — the same reach as paid ads would have cost
$7–14M. Creators on retainer, $1,000–2,000 a month each, each on a fresh TikTok/Instagram
account that only promotes the app.

They split the room themselves: **raised money → hire creators; not raised → founder-led
content and niche content accounts.** One creator at $1,000/month needs ~285 Pro sales a
month to pay back at $3.50. We are at two in three weeks. So: their tactics, our budget.

## The plan

### Phase 1 — our own content (now, $0)

The product's output is the content. A Milky Way stack or a star-trail time-lapse with
"this is an iPhone" is the hook by itself.

- **Shoot every dark night** on the road (mountains, desert, national parks): 3–5 shorts each.
- **Four formats** that the agency says work, in order of what they buy:
  1. *Educational* (converts, not just views): "3 settings for stars on iPhone".
  2. *POV*: "POV: you didn't know your iPhone could shoot this".
  3. *Story*: one night, from the drive to the finished time-lapse.
  4. *Comparison*: iPhone + Starlapse vs a $3,000 camera.
- **Hook in the first frame**: the finished sky, text on screen, a sound. Gen Z gives 0.1 s,
  millennials 0.5 s, boomers 1–2 s.
- **Cadence**: 1–2 a day minimum. Same vertical cut to TikTok, Reels and Shorts.
- **2–3 niche accounts**, one per audience: astrophotography, travel night skies, iPhone tips.
  Every account has someone it matches; that is the agency's whole reasoning for many accounts.
- **CTA in the comments, not the video**: "what app is this?" → reply with the name. Link
  in bio. A video that asks for the download every time gets scrolled.
- Background with depth, good light, energy, consistency: the four things they fix first
  in a weak creator. Detail matters (one creator: same video, blue shirt went viral, black
  did nothing).

### Phase 2 — paid creators, only after a signal

Trigger: one of our videos passes ~100k views **and** App Store Connect shows the installs
from its campaign link. Then 3–5 micro-creators from astro/travel, paid per video
($50–200) or a bonus per views (their norm: ~$1,000 per million). Retainer only once the
cost per install is known.

## Product levers (in the app)

- **"Shot on Starlapse" on free saves** — done 2026-10-20. Small, bottom right, Pro removes
  it. Every shared photo or time-lapse names the app. The dataset copy stays clean.
  `capture_saved` carries `watermark: true/false` so the effect is measurable.
- **Exposure time on the main screen** — done 2026-10-20. Auto + 1/5/15/60 min instead of
  a slider in the sheet. Auto is a rule by stack mode (see `LightPreset`).
- **Star names on the picture** — next. Optional, only the key stars and planets, placed
  from the plate solve rather than the compass so they sit on the right point. The overlay
  already exists live; burning it into the saved image is what makes the photo a post.
- Output is already portrait (`videoRotationAngle = 90`); 3:4 sits fine in a 9:16 feed.

## How to measure

- One App Store campaign link per platform and account:
  `https://apps.apple.com/app/apple-store/id6801191027?pt=128499174&ct=<platform>-<account>&mt=8`
  (`ct` up to 40 chars, e.g. `tiktok-astro`, `reels-travel`, `shorts-tips`). Installs per
  `ct` are in App Store Connect → App Analytics → Sources → Campaigns.
- In our analytics: launches, `capture_saved`, `paywall_shown`, `pro_purchased` by week.
- A week of posts per format before judging it. Views are attention; installs per campaign
  are the result. Percent swings at this volume are noise; multiples are a finding.
