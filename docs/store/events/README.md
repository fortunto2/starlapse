# In-App Events

Six events for the winter of 2026–27, each `SPECIAL_EVENT`, free, 175 territories, 11 locales,
two images per locale (16:9 card, 9:16 details page; no text on either). `events.json` holds
the schedule, the copy and the ASC id of each.

| Event | Promoted from | Runs (UTC) | Link |
|---|---|---|---|
| November Supermoon | 9 Nov | 23–25 Nov | `starlapse://moon` |
| Geminids | 28 Nov | 12–15 Dec | `starlapse://sky` |
| Christmas Eve Supermoon | 8 Dec | 22–26 Dec | `starlapse://moon` |
| Quadrantids | 20 Dec | 3–4 Jan | `starlapse://sky` |
| Wolf Supermoon | 8 Jan | 21–23 Jan | `starlapse://moon` |
| Lantern Festival Supermoon (+ Mars at opposition) | 6 Feb | 19–22 Feb | `starlapse://moon` |

Rules Apple enforces that are not obvious:
- **A deep link is required to submit**, and the reviewer taps it. The app had no URL scheme
  before 1.2.1; `DeepLink.swift` is why it exists. ASC accepts any URL when you save it.
- **Promotion starts at most 14 days before the event.** 14.5 is refused after the event is
  created, and `asc` deletes it again.
- **Territories are required.** Pass the app's full availability list.
- Copy limits: name 30, short 50, long 120 characters.

Media: `meteors.py` draws the showers; `moonscape.py` sets NASA's public-domain full Moon
(Goddard, LRO) over a ridge at dusk. Dates were checked against EarthSky, Star Walk, Sky at
Night and the IMO calendar on 7–8 Nov 2026; Chinese New Year (6 Feb 2027) is a new Moon, so
the lunar-calendar event is the Lantern Festival full Moon a fortnight later.
