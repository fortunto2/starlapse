# Localization

Ten store locales and nine app languages, chosen from where the downloads come from
(App Store Connect "App Downloads Standard", 27 Aug – 7 Oct 2026: India 43 first-time
downloads of 136, then US, UK, Singapore, China, Canada, Italy, Japan, France, Philippines,
Germany, Saudi Arabia, UAE, Turkey).

| | Locales |
|---|---|
| App Store listing | en-US, en-GB, hi, zh-Hans, ja, fr-FR, ar-SA, de-DE, it, tr, es-MX |
| App UI (`Localizable.xcstrings`, `InfoPlist.xcstrings`) | en, hi, zh-Hans, ja, fr, ar, de, it, tr, es |

## App strings

The source of truth is the English literal in the code. SwiftUI localizes `Text`, `Button`,
`Label` and `Picker` literals on its own; our `ReadoutRow`, `NightSlider`, `sectionTitle`
and `modeButton` take a `LocalizedStringKey` for the same reason. Anything that is a plain
`String` (enum titles, `String(format:)` templates, view-model messages) goes through
`String(localized:)`. Interpolated `Text("… \(x)")` is avoided: the generated key depends on
the interpolated type, so those are written as `String(format: String(localized: "… %@"), x)`
and the key is explicit.

```
python3 docs/l10n/extract.py > docs/l10n/en.json   # keys from the code (+ Info.plist prompts)
# translate: docs/l10n/<lang>.json, same keys, values in that language
python3 docs/l10n/build_catalog.py                  # writes both .xcstrings, checks specifiers
make build
```

`build_catalog.py` fails on a missing key or a translation whose printf specifiers differ
from the key. Add a language: a new `<lang>.json`, nothing else.

What stays English: SkyKit output (conditions summary, aim reason, shower and star names)
and units (s, min, px, fps, K, mag). SkyKit is a platform-free package without a resource
bundle, and the sentences it produces are read next to numbers. That is a known gap, not a
decision that they do not matter.

## Store listing

`docs/store/metadata/locales/<locale>/` holds the six fields per locale; `push.sh <version-id>`
creates or updates every locale on a version and sets the app-info subtitle. Limits that
App Store Connect enforces: subtitle 30, keywords 100, promotional text 170, description 4000.
Metadata lives on a version, so a locale added after a version is live needs a new version.
Locales without screenshots show the en-US set.

Keywords are per locale and all count for the storefront that lists that language, which is
the point: en-GB carries a second English keyword set (startrails, perseids, nightscape…) that
en-US has no room for, and India's storefront lists both English and Hindi.
