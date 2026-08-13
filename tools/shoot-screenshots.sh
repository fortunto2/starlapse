#!/bin/bash
# App Store screenshots from the Simulator.
#
# The Simulator has no camera, so the viewfinder would be a black rectangle. UITEST_SKY=1
# feeds a synthesised night sky through the real pipeline instead — same stacking, same
# alignment, same asinh curve — so what is captured is genuinely this app's output.
#
# What it does NOT do is fake results the app cannot produce. No comet, no meteor: those
# are rare, and a screenshot promising one promises a buyer something they will not get.
#
# Usage: tools/shoot-screenshots.sh [simulator-udid]
set -euo pipefail

SIM="${1:-A77824F6-B318-4BA5-8BDC-57259EC2AA8F}"   # iPhone 17 Pro
BID="co.superduperai.starlapse"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/store/screenshots"
SETTLE="${SETTLE:-11}"

mkdir -p "$OUT"
pause() { python3 -c "import time,sys; time.sleep(float(sys.argv[1]))" "$1"; }

echo "→ building"
xcodegen generate >/dev/null
xcodebuild -project "$ROOT/Starlapse.xcodeproj" -scheme Starlapse \
    -sdk iphonesimulator -destination "id=$SIM" \
    -derivedDataPath "$ROOT/build-sim" CODE_SIGNING_ALLOWED=NO build 2>&1 \
    | grep -E "(error:|BUILD SUCCEEDED)" | tail -1

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$ROOT/build-sim/Build/Products/Debug-iphonesimulator/Starlapse.app"

# Grant up front: a permission dialog sitting over the viewfinder ruins every shot.
xcrun simctl privacy "$SIM" grant photos "$BID" 2>/dev/null || true
xcrun simctl privacy "$SIM" grant location "$BID" 2>/dev/null || true
xcrun simctl privacy "$SIM" grant location-always "$BID" 2>/dev/null || true
xcrun simctl location "$SIM" set 28.754,-17.885 2>/dev/null || true

shoot() {
    local name="$1"; shift
    xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
    pause 1.5
    env "$@" xcrun simctl launch "$SIM" "$BID" >/dev/null 2>&1
    pause "$SETTLE"
    xcrun simctl io "$SIM" screenshot "$OUT/$name.png" >/dev/null 2>&1
    python3 -c "
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print(f'  {sys.argv[2]:22s} {im.size[0]}x{im.size[1]}')" "$OUT/$name.png" "$name" 2>/dev/null \
        || echo "  $name"
}

echo "→ shooting"
# 1. Aiming: the overlay with real computed planets and stars over a live sky.
shoot 01-aiming SIMCTL_CHILD_UITEST_SKY=1

# 2. Mid-stack: frames accumulating, tracking readout live.
shoot 02-stacking SIMCTL_CHILD_UITEST_SKY=1 SIMCTL_CHILD_UITEST_CAPTURE=1

# 3. Manual controls: the locked exposure panel.
shoot 03-controls SIMCTL_CHILD_UITEST_SKY=1 SIMCTL_CHILD_UITEST_PANEL=controls

# 4. Detector: watching for transients.
shoot 04-detector SIMCTL_CHILD_UITEST_SKY=1 SIMCTL_CHILD_UITEST_MODE=detector

echo "→ $OUT"
