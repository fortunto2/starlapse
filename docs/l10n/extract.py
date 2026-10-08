#!/usr/bin/env python3
"""Collect the English keys the app localizes.

Reads Sources/Starlapse/**/*.swift and prints one JSON object: key -> comment (the file it
came from). Keys are the literals SwiftUI localizes on its own (Text, Button, Label, Picker,
and our LocalizedStringKey parameters: label:, sectionTitle(, modeButton() plus every
String(localized:) call. Info.plist usage descriptions are added under a "plist:" prefix.

    python3 docs/l10n/extract.py > docs/l10n/en.json
"""
import json, pathlib, plistlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "Sources" / "Starlapse"
LITERAL = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [
    re.compile(r'(?<![A-Za-z.])Text\(\s*' + LITERAL),
    re.compile(r'(?<![A-Za-z.])Button\(\s*' + LITERAL),
    re.compile(r'(?<![A-Za-z.])Label\(\s*' + LITERAL),
    re.compile(r'(?<![A-Za-z.])Picker\(\s*' + LITERAL),
    re.compile(r'(?<![A-Za-z.])Toggle\(\s*' + LITERAL),
    re.compile(r'\blabel:\s*' + LITERAL),
    re.compile(r'\bsectionTitle\(\s*' + LITERAL),
    re.compile(r'\bmodeButton\(\s*' + LITERAL),
    re.compile(r'String\(\s*localized:\s*' + LITERAL),
]
# `label:` is also the name of a ForEach/Control field holding a plain String.
SKIP_FILES = {"ToneControls.swift"}

keys: dict[str, str] = {}
problems = []
for path in sorted(SRC.rglob("*.swift")):
    text = path.read_text()
    rel = str(path.relative_to(ROOT))
    for pattern in PATTERNS:
        for match in pattern.finditer(text):
            key = match.group(1)
            if path.name in SKIP_FILES and pattern.pattern.startswith(r"\blabel"):
                continue
            if not key.strip():
                continue
            if r"\(" in key:
                problems.append(f"{rel}: interpolation in key {key!r}")
                continue
            if "." in key and " " not in key and key.islower():
                continue  # an SF Symbol or identifier, not copy
            key = key.replace('\\"', '"').replace("\\n", "\n")
            keys.setdefault(key, rel)

# ToneControls labels are plain Strings wrapped in LocalizedStringKey at the call site.
for key in ("Stretch (asinh)", "Black point", "Exposure", "Saturation"):
    keys.setdefault(key, "Sources/Starlapse/Views/ToneControls.swift")

with open(SRC / "App" / "Info.plist", "rb") as handle:
    plist = plistlib.load(handle)
for name, value in plist.items():
    if name.endswith("UsageDescription"):
        keys[f"plist:{name}"] = value

for line in problems:
    print(line, file=sys.stderr)
json.dump(dict(sorted(keys.items())), sys.stdout, ensure_ascii=False, indent=1)
print()
