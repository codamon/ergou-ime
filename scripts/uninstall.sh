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
cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
if [[ -n "$cache" && -d "$cache" ]]; then
  while IFS= read -r f; do
    strings -a "$f" 2>/dev/null | grep -qF "$IM" && rm -f "${f%.kbdx}" "$f"
  done < <(find "$cache" -mindepth 2 -maxdepth 2 -name 'com.apple.IntlDataCache.le.kbdx' 2>/dev/null)
fi

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
echo "Done. Remove 二狗 from System Settings → Keyboard → Input Sources if it is still listed;"
echo "Microphone and Input Monitoring entries can be removed in Privacy & Security."
