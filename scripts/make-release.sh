#!/bin/bash
# Build a downloadable Window Festivizer: a universal Release build (Apple Silicon and Intel),
# zipped, and checked. Leaves build/Window-Festivizer.zip, ready to attach to a GitHub release.
#   scripts/make-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData
APP="$DERIVED/Build/Products/Release/WindowFestivizer.app"
ZIP=build/Window-Festivizer.zip

xcodebuild -project WindowFestivizer.xcodeproj -scheme WindowFestivizer -configuration Release \
  -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  clean build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/WindowFestivizer"))"

# No resource forks or extended attributes: they become stray "._" files that break the app's
# signature when the zip is opened with command-line unzip.
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

# Check the zip survives both ways of unzipping (Finder uses the same engine as ditto), and that
# the app inside is still correctly signed and runs: --render draws a preview and quits, without
# touching any windows or the copy you may have running.
for tool in ditto unzip; do
  tmp=$(mktemp -d)
  if [ "$tool" = ditto ]; then ditto -x -k "$ZIP" "$tmp"; else unzip -q "$ZIP" -d "$tmp"; fi
  codesign --verify --deep --strict "$tmp/WindowFestivizer.app" \
    || { echo "zip check failed: bad signature after $tool" >&2; exit 1; }
  "$tmp/WindowFestivizer.app/Contents/MacOS/WindowFestivizer" --render "$tmp/check.png" >/dev/null \
    || { echo "zip check failed: app didn't run after $tool" >&2; exit 1; }
  rm -rf "$tmp"
done
echo "Made $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' ')), checked with ditto and unzip"
