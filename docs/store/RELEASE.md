# Release

What it actually took to get 1.0 to the App Store, in the order it has to happen. Written
down because half of it is unobvious and none of it is worth rediscovering.

## Identifiers

```
app id      6801191027
bundle id   co.superduperai.starlapse   (KKUYK5RUN7)
team        8N495BBBLM
certificate A4WNUJC559                  iPhone Distribution, expires 2027-07-30
profile     Starlapse AppStore 2026     IOS_APP_STORE
group       aaff059c-981a-432a-a875-12803a76b7cb   TestFlight Internal
```

Machine-local values live in `Makefile.local` (gitignored).

## The pipeline

```bash
make test          # 43 domain tests, ~3s, no simulator
make test-app      # 5 app-layer tests on a simulator
make ipa           # archive → sign → export, one command
make testflight    # upload (needs APP_ID)
tools/shoot-screenshots.sh    # 4 screenshots from a synthesised sky
```

## What can be done from the CLI, and what cannot

Almost everything runs through `asc` with the API key in the Keychain. Three things need a
web session (Apple ID + 2FA) and cannot be automated:

| Needs a browser / web session | Why |
|---|---|
| Creating the app record | `asc web apps create` — reserves the name |
| **App Privacy declaration** | Not in the public API at all |
| Vision Pro availability toggle | Not in the public API |

Everything else — bundle ID, provisioning profile, categories, pricing, territories, age
rating, metadata, screenshots, review details, build attachment, submission — is CLI.

## Order of operations

`asc validate` is the source of truth, not the web UI. Its output *is* the task list.

```bash
asc validate --app 6801191027 --version "1.0" --platform IOS --output json | ...
```

1. `asc bundle-ids create` → `asc profiles create` (needs the bundle ID's internal id, not
   the reverse-DNS string)
2. `asc app-setup categories set --primary PHOTO_AND_VIDEO`
3. `asc age-rating edit --all-none` → 4+
4. `asc pricing availability create --territory "$(all 175)" ` then
   `asc pricing schedule create --free --start-date <today>`
   — availability and price are **separate** required items; the price is the classic miss
5. `asc apps update --content-rights DOES_NOT_USE_THIRD_PARTY_CONTENT`
6. `asc versions update --copyright`
7. `asc localizations update` — description, keywords, support URL, marketing URL
8. `asc app-setup info set` — subtitle, privacy policy URL
9. `asc review details-create` — contact plus reviewer notes
10. `asc screenshots upload`
11. `asc versions attach-build`
12. App Privacy in the browser
13. `asc review submit --dry-run`, then `--confirm`

## Traps, each of which cost time

**A profile is bound to one specific certificate.** "Apple Distribution" and "iPhone
Distribution" are different certificates. Using the wrong one fails with *"profile doesn't
include signing certificate"*, which reads like a missing profile and is not.

**`whatsNew` cannot be set on a first release.** There is nothing new about 1.0. Setting it
fails with *"the state of another resource"*, which names nothing useful.

**Territory lists paginate.** `asc pricing territories list` returns 50 of 175 without
`--paginate`, and the partial list fails mid-request on an unrelated-looking territory code.

**Screenshots need a locale subdirectory.** `screenshots/en-US/*.png`, not `screenshots/*.png`.

**`MTL_ENABLE_DEBUG_INFO` must be Debug-only.** Set globally it ships shader source inside
`default.metallib`, and App Store Connect flags the upload.

**Screenshot sizes are fixed and the newest simulators do not match them.** APP_IPHONE_65
wants 1284×2778; an iPhone 17 Pro shoots 1206×2622 and a 15 Plus 1290×2796. Scale to width
and trim, the aspect differs by half a percent.

## Reviewer notes

An astrophotography app tested indoors in daylight looks broken — the viewfinder is dark
because exposure is locked for night sky work. The review notes lead with that, then list
what a reviewer can verify without a night sky: the manual controls hold their values, the
modes switch, and the sky overlay computes real planet and radiant positions indoors,
because that is astronomy rather than image recognition.

## Screenshots

Generated from a synthesised sky (`StubSkySource`, DEBUG only, verified absent from the
Release binary) fed through the real pipeline — same stacking, same alignment, same asinh
curve. The stars rotate at the true sidereal rate so the aligner has something real to
solve; the numbers visible in the shots are measured, not drawn.

A meteor crosses the frame because that is what the app is built to catch. There is no
comet: those come every few years, and a screenshot promising one promises a buyer
something they will not get.
