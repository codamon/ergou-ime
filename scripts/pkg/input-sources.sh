#!/bin/bash
# ergou-ime — make 二狗 show up as an enabled input source. Run as the user.
# SPDX-License-Identifier: GPL-3.0-only
#
#   input-sources.sh /path/to/ErgouIME.app
#
# Used by the .pkg postinstall, scripts/install.sh and
# scripts/migrate-from-quiet-ime.sh. TISEnableInputSource from an installer
# or SSH session often does not reach the user's saved list
# (com.apple.HIToolbox AppleEnabledInputSources): the source then shows in
# the input menu but greyed out. So, after registering:
#   1. TISEnableInputSource through the app (in the GUI session if possible);
#   2. add the bundle and the Wubi input mode to AppleEnabledInputSources if
#      they are still missing;
#   3. drop entries of the old name (com.codamon.inputmethod.QuietIME*) from
#      AppleEnabledInputSources, AppleInputSourceHistory and
#      AppleSelectedInputSources;
#   4. restart TextInputMenuAgent so the menu reloads.
set -uo pipefail
app="${1:?usage: input-sources.sh ErgouIME.app}"
BUNDLE=com.codamon.inputmethod.Ergou
MODE=com.codamon.inputmethod.Ergou.Wubi
OLD=com.codamon.inputmethod.QuietIME
bin="$app/Contents/MacOS/ErgouIME"

# run_briefly CMD…: never hang an installer (an older binary that does not
# know a flag would start the input method server instead of exiting).
run_briefly() {
  "$@" >/dev/null 2>&1 & local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && (( i < 50 )); do sleep 0.1; i=$((i + 1)); done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
run_briefly "$bin" --register-input-source
run_briefly "$bin" --enable-input-source-only
# Same again in the GUI session (no-op if the IM is already running there).
open -n -g "$app" --args --enable-input-source-only >/dev/null 2>&1 || true
sleep 1

tmp="$(mktemp -t ergou-hitoolbox)"
defaults export com.apple.HIToolbox "$tmp" 2>/dev/null || plutil -create xml1 "$tmp" 2>/dev/null || echo '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$tmp"
pb() { /usr/libexec/PlistBuddy -c "$1" "$tmp" >/dev/null 2>&1; }

# Remove old-name entries (walk backwards so indices stay valid).
for key in AppleEnabledInputSources AppleInputSourceHistory AppleSelectedInputSources; do
  n=0; while /usr/libexec/PlistBuddy -c "Print :$key:$n" "$tmp" >/dev/null 2>&1; do n=$((n + 1)); done
  i=$((n - 1))
  while (( i >= 0 )); do
    id="$(/usr/libexec/PlistBuddy -c "Print :$key:$i:Bundle\ ID" "$tmp" 2>/dev/null || true)"
    [[ "$id" == "$OLD"* ]] && pb "Delete :$key:$i"
    i=$((i - 1))
  done
done

has() {   # has KIND [MODE]
  local i=0 b k m
  while /usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$i" "$tmp" >/dev/null 2>&1; do
    b="$(/usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$i:Bundle\ ID" "$tmp" 2>/dev/null || true)"
    k="$(/usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$i:InputSourceKind" "$tmp" 2>/dev/null || true)"
    m="$(/usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$i:Input\ Mode" "$tmp" 2>/dev/null || true)"
    [[ "$b" == "$BUNDLE" && "$k" == "$1" && "$m" == "${2:-}" ]] && return 0
    i=$((i + 1))
  done
  return 1
}
pb "Add :AppleEnabledInputSources array"
changed=0
if ! has "Keyboard Input Method"; then
  pb "Add :AppleEnabledInputSources:0 dict"
  pb "Add :AppleEnabledInputSources:0:Bundle\ ID string $BUNDLE"
  pb "Add :AppleEnabledInputSources:0:InputSourceKind string Keyboard\ Input\ Method"
  changed=1
fi
if ! has "Input Mode" "$MODE"; then
  pb "Add :AppleEnabledInputSources:0 dict"
  pb "Add :AppleEnabledInputSources:0:Bundle\ ID string $BUNDLE"
  pb "Add :AppleEnabledInputSources:0:Input\ Mode string $MODE"
  pb "Add :AppleEnabledInputSources:0:InputSourceKind string Input\ Mode"
  changed=1
fi
defaults import com.apple.HIToolbox "$tmp"
rm -f "$tmp"
(( changed )) && echo "added 二狗 to the enabled input sources"
# imklaunchagent caches the bundle's Launch Services unit; after the app is
# replaced it looks up a unit that no longer exists, reads no
# InputMethodConnectionName and refuses the input method ("Refusing
# connection name …", 二狗 greyed out — D's Mac, macOS 27, 2026-11-10).
# It is a launchd agent and restarts on demand.
killall imklaunchagent 2>/dev/null || true
killall TextInputMenuAgent 2>/dev/null || true
exit 0
