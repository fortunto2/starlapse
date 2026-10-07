# Product page test: captioned screenshots

Started 6 October 2026 against the live 1.0.2 page (experiment `e7ccaf29-dbdd-40bc-bb1b-b8526d265a2a`,
66% of eligible traffic split across the treatments). The control is the raw simulator shots.

| Treatment | Frames |
|---|---|
| `captions/` | the four live shots, each under a headline and one line of copy |
| `result-first/` | stacking first, then aiming, tonight's events (the Pro row), controls, detector |

`generate.py` renders both from `../0N-*.png` with Pillow and the JetBrains Mono Nerd Font from
`~/Library/Fonts`. Output is 1284×2778, the 6.5-inch size the live set uses; 1206×2622 is what
the simulator produces and what App Store Connect was given in August, which it upscaled.

The API has no CLI for this in `asc`. Creating one is: `POST /v2/appStoreVersionExperiments`
(type `appStoreVersionExperiments`, relationship `app`), then treatments, then a localization per
treatment. The localization arrives with the control's screenshot sets copied in, so the frames are
deleted and replaced rather than a set created. `PATCH {started: true}` submits it for review.
