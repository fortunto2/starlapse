# Starlapse Pro — one-time unlock for sky events

Decision (Rustam, 2026-10-06): constant objects (planets, bright stars, Moon) stay free;
events with aim guidance (meteor showers: where to point, peak nights, Moon-free windows)
go behind a one-time non-consumable purchase. Nothing that shipped free is removed.

Product: `co.superduperai.starlapse.pro`, NON_CONSUMABLE, $4.99 base (US), Apple equalises
other territories. Reference name "Starlapse Pro".

## Tasks

- [x] P1 IAP created in ASC (`asc iap setup`), localization + review screenshot later
- [x] P2 `Entitlements` (@MainActor @Observable, StoreKit 2): isPro, purchase(), restore(), transaction listener
- [x] P3 Gate: `CaptureViewModel.showsEvents`; overlay hides radiant + target + guidance; status panel shows teaser + Unlock
- [x] P4 `ProPaywallView`: what you get, price from StoreKit, Buy / Restore, privacy line
- [x] P5 `Starlapse.storekit` config + scheme option so the simulator can buy
- [x] P6 Tests: gating logic pure function; StoreKitTest purchase → isPro
- [x] P7 Description (1.0.3): PRIVACY paragraph mentions the one Apple call; Pro section
- [x] P8 Build, lint, screenshots of paywall on simulator, commit
- [x] P9 App Privacy: check whether "Purchases" needs declaring (StoreKit only: no)
- [x] P10 Review 1.0.3 (13) rejected, 3.1.1: Restore lived only on the paywall, and the paywall
  opened only from the event row, which needs location and an active shower. On the review
  iPad there was neither. Build 15: STARLAPSE PRO section in settings with UNLOCK PRO and
  RESTORE PURCHASE, always present; paywall Restore is a bordered button. Rule: every purchase
  entry point must be reachable with every permission denied.
- [x] P11 1.0.4: the paywall promised "peak nights" and the app showed one line. `SkyDirector.forecast`
  walks every night of every shower window for the location (20-minute steps, astronomical
  night only) and returns best night, hour, rate, radiant, Moon and a verdict; `EventsView`
  lists the season, `eventsRow` names the next one above the shutter (free sees name and
  date, Pro the sheet). CLI: `starlapse-sky events`. Milky Way drawn as the galactic equator
  (free, it is constant sky). Store and app localized for the download countries.

## Free vs Pro

Free: manual camera, stacking (pinpoint / trails / landscape), time-lapse, meteor detector,
overlay with planets, bright stars, Moon, horizon, compass readout, focus target.

Pro: tonight's events — active showers with expected rate, "AIM HERE" target computed
40° off the radiant and clear of the Moon, guidance arrow, peak-night and Moon-window
text. Future events (comets, conjunctions, eclipses) and dark frames / comet trails ship to
Pro at no extra cost.
