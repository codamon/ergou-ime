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
#   2. macOS 27 and later: remove our entries from com.apple.HIToolbox
#      AppleEnabledInputSources (the system keeps third-party input methods
#      in com.apple.inputsources; being in both lists the input mode
#      twice); older systems: add the bundle and the input mode there if
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
# Without the current list, stop here: importing a list made from an empty
# plist could replace the user's other enabled input sources.
if ! defaults export com.apple.HIToolbox "$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
  echo "could not read com.apple.HIToolbox; enabled input sources left as they are"
  rm -f "$tmp"
  killall imklaunchagent 2>/dev/null || true
  killall TextInputMenuAgent 2>/dev/null || true
  exit 0
fi
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
# macOS 27 keeps third-party input methods in com.apple.inputsources
# (AppleEnabledThirdPartyInputSources). There we must NOT also be in
# com.apple.HIToolbox: with both, the system lists the input mode twice — one
# extra TIS source on D's Mac, 14 rows of 二狗 in System Settings on a user's
# (found 2026-11-11 on macOS 27.0.1: removing our HIToolbox entries brought
# the count back to normal with 二狗 still enabled). So on macOS 27 and later
# this script never writes our entries into HIToolbox and removes the ones an
# older installer wrote. Decided by OS version, not by "the new list has us":
# only 27 was tested, and on older systems both lists may hold an input
# method normally — those keep the old behaviour below.
major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
listed() {
  defaults read com.apple.inputsources AppleEnabledThirdPartyInputSources 2>/dev/null | grep -F "\"$BUNDLE\"" >/dev/null
}
if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 27 )); then
  # TISEnableInputSource (above) lands a moment later.
  for _ in 1 2 3 4 5 6 7 8 9 10; do listed && break; sleep 0.5; done
  if listed; then
    n=0; while /usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$n" "$tmp" >/dev/null 2>&1; do n=$((n + 1)); done
    i=$((n - 1)); removed=0
    while (( i >= 0 )); do
      id="$(/usr/libexec/PlistBuddy -c "Print :AppleEnabledInputSources:$i:Bundle\ ID" "$tmp" 2>/dev/null || true)"
      if [[ "$id" == "$BUNDLE" ]]; then pb "Delete :AppleEnabledInputSources:$i"; removed=$((removed + 1)); fi
      i=$((i - 1))
    done
    if (( removed )); then
      defaults import com.apple.HIToolbox "$tmp"
      echo "removed $removed duplicate 二狗 entries from com.apple.HIToolbox"
    fi
  else
    echo "二狗 is not enabled yet: add it in System Settings › Keyboard › Input Sources"
  fi
  rm -f "$tmp"
  killall imklaunchagent 2>/dev/null || true
  killall TextInputMenuAgent 2>/dev/null || true
  exit 0
fi

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
