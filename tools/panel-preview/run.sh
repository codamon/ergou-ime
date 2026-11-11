#!/usr/bin/env bash
# ergou-ime — build and run the candidate window preview (macOS only).
# SPDX-License-Identifier: GPL-3.0-only
#
#   ./tools/panel-preview/run.sh [OUT_DIR]
#
# Writes one PNG per scene and contrast.json to OUT_DIR (an absolute path;
# default build/panel-preview/out). Windows appear on screen for about half
# a minute. ONLY, TINT and SCREEN=1x are described in main.swift.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$repo/build/panel-preview"
out="${1:-$work/out}"
app="$work/PanelPreview.app"
rm -rf "$work"; mkdir -p "$app/Contents/MacOS" "$out" "$work/src"
# The preview reads the panel's item rectangles and moves the HUD's window,
# which are private.
for f in CandidatePanel VoiceHUD; do
  sed 's/private //g' "$repo/ErgouIME/UI/$f.swift" > "$work/src/$f.swift"
done
swiftc -swift-version 5 -Onone -module-cache-path "$work/module-cache" -o "$app/Contents/MacOS/PanelPreview" \
  "$repo/tools/panel-preview/main.swift" "$work/src/CandidatePanel.swift" "$work/src/VoiceHUD.swift" \
  "$repo/ErgouIME/UI/Surface.swift"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ergou.panel-preview</string>
<key>CFBundleExecutable</key><string>PanelPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
open -W -n "$app" --env "ONLY=${ONLY:-}" --env "TINT=${TINT:-}" --env "SCREEN=${SCREEN:-}" --stdout "$work/log.txt" --stderr "$work/log.txt" --args "$out"
cat "$work/log.txt"
ls "$out" | wc -l
