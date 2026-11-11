#!/bin/bash
# ergou-ime — uninstall 二狗输入法.
# SPDX-License-Identifier: GPL-3.0-only
#
#   bash uninstall.sh              remove the app; keep settings, models, 我的词
#   bash uninstall.sh --all        also delete all data (lists it first and asks)
#
# Run as yourself, not with sudo. A copy in /Library/Input Methods (all users)
# is removed too if you own it; otherwise the script prints the sudo command.
set -euo pipefail
purge=0; [[ "${1:-}" == "--all" ]] && purge=1
[[ $EUID -ne 0 ]] || { echo "run as your own user, not root"; exit 1; }

IM=com.codamon.inputmethod.Ergou
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

pkill -x ErgouIME 2>/dev/null || true
pkill -f 'ErgouIME Settings.app/Contents/MacOS/' 2>/dev/null || true
pkill -x ErgouIMECorrector 2>/dev/null || true
pkill -x ErgouIMECloud 2>/dev/null || true

for app in "$HOME/Library/Input Methods/ErgouIME.app" "/Library/Input Methods/ErgouIME.app"; do
  [[ -d "$app" ]] || continue
  "$lsregister" -u "$app/Contents/Library/LoginItems/ErgouIME Settings.app" 2>/dev/null || true
  "$lsregister" -u "$app" 2>/dev/null || true
  if rm -rf "$app" 2>/dev/null && [[ ! -e "$app" ]]; then
    echo "removed $app"
  else
    echo "could not remove $app; run: sudo rm -rf '$app'"
  fi
done
# Installer receipt of the .pkg (per-user installs keep it in the home domain).
pkgutil --volume "$HOME" --forget "$IM.pkg" >/dev/null 2>&1 || true
pkgutil --forget "$IM.pkg" >/dev/null 2>&1 || true

# Input source tables of sandboxed apps that still list us (apps rebuild them).
# grep reads to the end (no -q): with pipefail, an early exit kills strings
# with SIGPIPE and the match would count as a failure.
cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
if [[ -n "$cache" && -d "$cache" ]]; then
  while IFS= read -r f; do
    strings -a "$f" 2>/dev/null | grep -F "$IM" >/dev/null && rm -f "${f%.kbdx}" "$f"
  done < <(find "$cache" -mindepth 2 -maxdepth 2 -name 'com.apple.IntlDataCache.le.kbdx' 2>/dev/null)
fi

# Take 二狗 out of the enabled / selected input sources, so nothing of it is
# left in System Settings and a later reinstall starts clean. Only our own
# entries are removed; without the current list nothing is changed.
for domain in com.apple.HIToolbox com.apple.inputsources; do
  tmp="$(mktemp -t ergou-uninstall-plist)"
  if defaults export "$domain" "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    removed=0
    for key in AppleEnabledInputSources AppleSelectedInputSources AppleInputSourceHistory AppleEnabledThirdPartyInputSources; do
      n=0; while /usr/libexec/PlistBuddy -c "Print :$key:$n" "$tmp" >/dev/null 2>&1; do n=$((n + 1)); done
      i=$((n - 1))
      while (( i >= 0 )); do
        id="$(/usr/libexec/PlistBuddy -c "Print :$key:$i:Bundle\ ID" "$tmp" 2>/dev/null || true)"
        if [[ "$id" == "$IM" ]]; then
          /usr/libexec/PlistBuddy -c "Delete :$key:$i" "$tmp" >/dev/null 2>&1 && removed=$((removed + 1))
        fi
        i=$((i - 1))
      done
    done
    if (( removed > 0 )); then defaults import "$domain" "$tmp" && echo "removed $removed input source entries from $domain"; fi
  fi
  rm -f "$tmp"
done
killall TextInputMenuAgent 2>/dev/null || true

if (( purge )); then
  data=()
  for c in "$IM" "$IM.Cloud" "$IM.Corrector" com.codamon.ErgouSettings; do
    [[ -e "$HOME/Library/Containers/$c" ]] && data+=("$HOME/Library/Containers/$c")
  done
  for g in "$HOME/Library/Group Containers/"*.com.codamon.ergou; do
    [[ -e "$g" ]] && data+=("$g")
  done
  if (( ${#data[@]} )); then
    echo "This deletes settings, 常用语, 我的词, voice history, typing history (调频),"
    echo "downloaded models and the cloud API key files:"
    for d in "${data[@]}"; do printf '    %s (%s)\n' "$d" "$(du -sh "$d" 2>/dev/null | cut -f1)"; done
    read -r -p "Delete? [y/N] " answer
    if [[ "$answer" == y || "$answer" == Y ]]; then
      for d in "${data[@]}"; do rm -rf "$d" 2>/dev/null || echo "could not delete $d (delete it in Finder)"; done
    fi
  fi
fi
echo "Done. 二狗输入法已卸载。If 二狗 is still listed in System Settings → Keyboard → Input Sources,"
echo "remove it there (or log out and back in). Microphone and Input Monitoring entries can be"
echo "removed in Privacy & Security. 可以关掉这个窗口了。"
