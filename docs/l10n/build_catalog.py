#!/usr/bin/env python3
"""Assemble the two String Catalogs from docs/l10n/<lang>.json.

    python3 docs/l10n/build_catalog.py

en.json holds the keys (key -> source file). Every other <lang>.json holds key -> translation
for one language, and must cover exactly the same keys. Keys prefixed "plist:" go to
InfoPlist.xcstrings (the catalog iOS reads for permission prompts), everything else to
Localizable.xcstrings. The English value of a plist key is taken from Info.plist, because in
that catalog the key is the plist key, not the English sentence.

Specifier check: a translation must use the same printf specifiers as its key. Positional
forms (%1$d) count as the same specifier; the check is the multiset of conversions.
"""
import json, pathlib, plistlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RES = ROOT / "Sources" / "Starlapse" / "Resources"
SPEC = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(l{0,2}[dfs@u]|%)")

def specifiers(text: str) -> list[str]:
    return sorted(m.group(1).lstrip("l") for m in SPEC.finditer(text))

en = json.loads((HERE / "en.json").read_text())
with open(ROOT / "Sources" / "Starlapse" / "App" / "Info.plist", "rb") as handle:
    plist = plistlib.load(handle)

languages = sorted(p.stem for p in HERE.glob("*.json") if p.stem != "en" and "-en" not in p.stem)
localizable: dict = {}
infoplist: dict = {}
for key in en:
    if key.startswith("plist:"):
        name = key.split(":", 1)[1]
        infoplist[name] = {"localizations": {"en": {"stringUnit": {"state": "translated", "value": plist[name]}}}}
    else:
        localizable[key] = {"localizations": {}}

errors = 0
for lang in languages:
    table = json.loads((HERE / f"{lang}.json").read_text())
    table = {k: v for k, v in table.items() if k.strip()}
    missing = set(en) - set(table)
    extra = set(table) - set(en)
    if extra:
        print(f"{lang}: {len(extra)} keys not in en.json, e.g. {sorted(extra)[:3]}", file=sys.stderr)
        errors += 1
    if missing:
        # Untranslated keys fall back to English on the device; said out loud, not failed,
        # so a new string can ship before every language catches up.
        print(f"{lang}: {len(missing)} keys untranslated, e.g. {sorted(missing)[:3]}", file=sys.stderr)
    for key, value in table.items():
        if key not in en or not isinstance(value, str) or not value.strip():
            continue
        if not key.startswith("plist:") and specifiers(value) != specifiers(key):
            print(f"{lang}: specifier mismatch\n  key   {key!r}\n  value {value!r}", file=sys.stderr)
            errors += 1
            continue
        unit = {"stringUnit": {"state": "translated", "value": value}}
        if key.startswith("plist:"):
            infoplist[key.split(":", 1)[1]]["localizations"][lang] = unit
        else:
            localizable[key]["localizations"][lang] = unit

for key, entry in localizable.items():
    if not entry["localizations"]:
        del entry["localizations"]

def write(path: pathlib.Path, strings: dict) -> None:
    catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=False) + "\n")
    print(f"{path.relative_to(ROOT)}: {len(strings)} keys, {len(languages)} languages")

RES.mkdir(parents=True, exist_ok=True)
write(RES / "Localizable.xcstrings", localizable)
write(RES / "InfoPlist.xcstrings", infoplist)
sys.exit(1 if errors else 0)
