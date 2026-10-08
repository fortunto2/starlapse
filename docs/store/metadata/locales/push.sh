#!/usr/bin/env bash
# Push every locale directory here to one App Store Connect version and to the app info.
#
#   docs/store/metadata/locales/push.sh <version-id>
#
# A locale that the version does not have yet is created; an existing one is updated.
# App-level fields (subtitle) go through the app-info localization; the name stays Starlapse.
# Screenshots are not touched: locales without their own fall back to en-US on the store.
set -euo pipefail
VERSION_ID="${1:?version id}"
APP=6801191027
HERE="$(cd "$(dirname "$0")" && pwd)"
existing="$(asc localizations list --version "$VERSION_ID" --output json | python3 -c '
import sys, json
raw = sys.stdin.read(); d = json.loads(raw[raw.find("{"):])
print(" ".join(l["attributes"]["locale"] for l in d["data"]))')"
for dir in "$HERE"/*/; do
  locale="$(basename "$dir")"
  desc="$(cat "$dir/description.txt")"; kw="$(tr -d '\n' < "$dir/keywords.txt")"
  promo="$(tr -d '\n' < "$dir/promotional-text.txt")"; new="$(cat "$dir/whats-new.txt")"
  sub="$(tr -d '\n' < "$dir/subtitle.txt")"
  if [[ " $existing " == *" $locale "* ]]; then verb=update; else verb=create; fi
  echo "== $locale ($verb)"
  asc localizations "$verb" --version "$VERSION_ID" --locale "$locale" \
    --description "$desc" --keywords "$kw" --promotional-text "$promo" --whats-new "$new" \
    --support-url "https://github.com/fortunto2/starlapse/issues" \
    --marketing-url "https://github.com/fortunto2/starlapse" >/dev/null
  asc localizations update --app "$APP" --type app-info --locale "$locale" --subtitle "$sub" >/dev/null \
    || echo "   app-info subtitle for $locale failed (see above)"
done
echo "done: $(ls -d "$HERE"/*/ | wc -l | tr -d ' ') locales"
