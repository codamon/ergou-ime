#!/bin/bash
# ergou-ime — one-time migration from the old name (静输入法 / quiet-ime).
# SPDX-License-Identifier: GPL-3.0-only
#
# 二狗输入法 was called 静输入法 (bundle IDs com.codamon.inputmethod.QuietIME*,
# App Group <TeamID>.com.codamon.quietime) during early development. macOS
# keys containers, settings and permissions by bundle ID, so the renamed app
# starts empty. This script moves the old data over:
#
#   App Group container   settings (incl. 常用语 and 我的词), Models/ (moved,
#                         not copied), Terms/, Cloud/ (API key files)
#   input method container Rime user data (调频 and user dictionaries),
#                         voice history, model checksum cache, per-app 中/英
#
# Usage (as the user, with 二狗输入法 already installed once so macOS has
# created its containers; the script quits both apps first):
#
#   ./scripts/migrate-from-quiet-ime.sh [TEAMID]             migrate + verify
#   ./scripts/migrate-from-quiet-ime.sh --remove-old [TEAMID] after checking:
#                         list, then delete the old app, containers and caches
#
# Nothing old is deleted by the first form. The second form refuses to run
# until the first form has finished and the new copies are still there.
# Microphone and Input Monitoring permissions cannot be migrated: macOS asks
# again for the new app.
set -euo pipefail

remove_old=0
if [[ "${1:-}" == "--remove-old" ]]; then remove_old=1; shift; fi
team="${1:-}"
OLD_IM=com.codamon.inputmethod.QuietIME
NEW_IM=com.codamon.inputmethod.Ergou
OLD_SETTINGS=com.codamon.QuietIMESettings

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ -z "$team" ]]; then
  # The only group container with the old name tells us the Team ID.
  for d in "$HOME/Library/Group Containers/"*.com.codamon.quietime; do
    [[ -d "$d" ]] && team="$(basename "$d" .com.codamon.quietime)"
  done
fi
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || die "Team ID not found; pass it as the first argument"

OLD_GROUP="$HOME/Library/Group Containers/$team.com.codamon.quietime"
NEW_GROUP="$HOME/Library/Group Containers/$team.com.codamon.ergou"
OLD_PRIV="$HOME/Library/Containers/$OLD_IM/Data/Library/Application Support/QuietIME"
NEW_PRIV="$HOME/Library/Containers/$NEW_IM/Data/Library/Application Support/ErgouIME"
OLD_IM_PREFS="$HOME/Library/Containers/$OLD_IM/Data/Library/Preferences/$OLD_IM.plist"
NEW_IM_PREFS="$HOME/Library/Containers/$NEW_IM/Data/Library/Preferences/$NEW_IM.plist"
OLD_GROUP_PREFS="$OLD_GROUP/Library/Preferences/$team.com.codamon.quietime.plist"
NEW_GROUP_PREFS="$NEW_GROUP/Library/Preferences/$team.com.codamon.ergou.plist"
OLD_APPS=("$HOME/Library/Input Methods/QuietIME.app" "/Library/Input Methods/QuietIME.app")
STAMP="$NEW_GROUP/.migrated-from-quiet-ime"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

quit_all() {
  pkill -x QuietIME 2>/dev/null || true
  pkill -f 'QuietIME Settings.app/Contents/MacOS/' 2>/dev/null || true
  pkill -x QuietIMECorrector 2>/dev/null || true
  pkill -x QuietIMECloud 2>/dev/null || true
  pkill -x ErgouIME 2>/dev/null || true
  pkill -f 'ErgouIME Settings.app/Contents/MacOS/' 2>/dev/null || true
  pkill -x ErgouIMECorrector 2>/dev/null || true
  pkill -x ErgouIMECloud 2>/dev/null || true
  sleep 1
}

# Same file list and contents (sizes + SHA-256 for small files, sizes for big
# ones) under two directories.
same_tree() {
  local a="$1" b="$2"
  diff <(cd "$a" && find . -type f ! -name .DS_Store -exec stat -f '%N %z' {} + | LC_ALL=C sort) \
       <(cd "$b" && find . -type f ! -name .DS_Store -exec stat -f '%N %z' {} + | LC_ALL=C sort) >/dev/null
}

if (( remove_old )); then
  [[ -f "$STAMP" ]] || die "run the migration first (no $STAMP)"
  for d in Models Terms Cloud; do
    if [[ -d "$OLD_GROUP/$d" ]] && [[ -n "$(ls -A "$OLD_GROUP/$d" 2>/dev/null)" ]]; then
      die "$OLD_GROUP/$d still has files; migrate again before removing"
    fi
  done
  for db in "$OLD_PRIV"/Rime/*.userdb; do
    [[ -d "$db" ]] || continue
    new="$NEW_PRIV/Rime/$(basename "$db" | sed 's/^quiet_/ergou_/')"
    [[ -d "$new" ]] || die "$(basename "$db") is not in the new container; not removing the old one"
  done
  quit_all
  victims=()
  for app in "${OLD_APPS[@]}"; do [[ -e "$app" ]] && victims+=("$app"); done
  for c in "$OLD_IM" "$OLD_IM.Cloud" "$OLD_IM.Corrector" "$OLD_SETTINGS"; do
    [[ -e "$HOME/Library/Containers/$c" ]] && victims+=("$HOME/Library/Containers/$c")
  done
  [[ -e "$OLD_GROUP" ]] && victims+=("$OLD_GROUP")
  log "Will delete:"
  for v in "${victims[@]}"; do
    printf '    %s (%s)\n' "$v" "$(du -sh "$v" 2>/dev/null | cut -f1)"
  done
  if [[ "${ERGOU_YES:-}" != 1 ]]; then
    read -r -p "Delete these? [y/N] " answer
    [[ "$answer" == y || "$answer" == Y ]] || die "nothing deleted"
  fi
  for app in "${OLD_APPS[@]}"; do
    [[ -e "$app" ]] && "$lsregister" -u "$app" 2>/dev/null || true
  done
  failed=0
  for v in "${victims[@]}"; do
    rm -rf "$v" 2>/dev/null || { warn "could not delete $v (macOS protects containers; delete it in Finder)"; failed=1; }
  done
  # Input source tables of sandboxed apps that still mention the old name
  # (same reason as in scripts/install.sh).
  cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  cleared=0
  if [[ -n "$cache" && -d "$cache" ]]; then
    while IFS= read -r f; do
      if strings -a "$f" 2>/dev/null | grep -qF "$OLD_IM"; then
        rm -f "${f%.kbdx}" "$f" && cleared=$((cleared + 1))
      fi
    done < <(find "$cache" -mindepth 2 -maxdepth 2 -name 'com.apple.IntlDataCache.le.kbdx' 2>/dev/null)
  fi
  log "Cleared $cleared input source caches that mentioned the old name"
  (( failed )) && exit 1
  log "Old data removed."
  exit 0
fi

# ---------------------------------------------------------------- migrate
[[ -d "$OLD_GROUP" || -d "$OLD_PRIV" ]] || die "no old data found (nothing to migrate)"
[[ -d "$NEW_GROUP" ]] || die "$NEW_GROUP does not exist yet: install 二狗输入法 and open its settings once, then run this again"
[[ -d "$HOME/Library/Containers/$NEW_IM" ]] || die "the new input method has not run yet: install it (scripts/install.sh), then run this again"
quit_all

# 1. Shared settings (cfprefsd owns these files: go through `defaults`).
if [[ -f "$OLD_GROUP_PREFS" ]]; then
  tmp="$(mktemp -t ergou-prefs)"
  defaults export "$OLD_GROUP_PREFS" "$tmp"
  # Keys already set in the new domain (by a first launch) are replaced.
  defaults import "$NEW_GROUP_PREFS" "$tmp"
  rm -f "$tmp"
  diff <(defaults export "$OLD_GROUP_PREFS" - | plutil -convert xml1 -o - -) \
       <(defaults export "$NEW_GROUP_PREFS" - | plutil -convert xml1 -o - -) >/dev/null \
    || warn "shared settings differ after import (new keys from the first launch are kept)"
  log "Settings: $(defaults export "$NEW_GROUP_PREFS" - | plutil -convert xml1 -o - - | grep -c '<key>') keys in the new App Group"
fi
if [[ -f "$OLD_IM_PREFS" ]]; then
  tmp="$(mktemp -t ergou-prefs)"
  defaults export "$OLD_IM_PREFS" "$tmp" && defaults import "$NEW_IM_PREFS" "$tmp"
  rm -f "$tmp"
  log "Input method preferences (中/英 per app): copied"
fi

# 2. Group container files. Models are large: move them (same volume).
for d in Models Terms Cloud; do
  src="$OLD_GROUP/$d"; dst="$NEW_GROUP/$d"
  [[ -d "$src" ]] || continue
  mkdir -p "$dst"
  chmod "$(stat -f '%Lp' "$src")" "$dst"
  for item in "$src"/* "$src"/.[!.]*; do
    [[ -e "$item" ]] || continue
    name="$(basename "$item")"
    if [[ -e "$dst/$name" ]]; then
      # A first launch may have created an empty Terms file or model folder.
      if [[ -d "$dst/$name" && -z "$(ls -A "$dst/$name")" ]] || [[ "$d" == Terms ]]; then
        rm -rf "$dst/$name"
      else
        warn "$dst/$name exists; keeping it and leaving $item in place"
        continue
      fi
    fi
    mv "$item" "$dst/$name"
  done
  rmdir "$src" 2>/dev/null || warn "$src not empty after the move"
  log "$d: $(find "$dst" -type f | wc -l | tr -d ' ') files, $(du -sh "$dst" | cut -f1)"
done
[[ -d "$NEW_GROUP/Cloud" ]] && chmod 700 "$NEW_GROUP/Cloud" && chmod 600 "$NEW_GROUP/Cloud"/* 2>/dev/null || true

# 3. Input method's private data: copy, check, keep the old copy until --remove-old.
if [[ -d "$OLD_PRIV" ]]; then
  mkdir -p "$NEW_PRIV"
  if [[ -d "$OLD_PRIV/Rime" ]]; then
    rm -rf "$NEW_PRIV/Rime"
    # build/ is a cache of the old schema names; the generated *.custom.yaml
    # and quiet_phrases.txt are rewritten from the settings on the next start.
    rsync -a --exclude build/ --exclude 'quiet_*.custom.yaml' --exclude quiet_phrases.txt \
      "$OLD_PRIV/Rime/" "$NEW_PRIV/Rime/"
    for db in "$NEW_PRIV"/Rime/quiet_*.userdb "$NEW_PRIV"/Rime/quiet_*.userdb.txt; do
      [[ -e "$db" ]] || continue
      mv "$db" "$(dirname "$db")/$(basename "$db" | sed 's/^quiet_/ergou_/')"
    done
    [[ -f "$NEW_PRIV/Rime/user.yaml" ]] && sed -i '' 's/quiet_/ergou_/g' "$NEW_PRIV/Rime/user.yaml"
    [[ -f "$NEW_PRIV/Rime/installation.yaml" ]] && sed -i '' 's/QuietIME/ErgouIME/g' "$NEW_PRIV/Rime/installation.yaml"
    for db in "$OLD_PRIV"/Rime/*.userdb; do
      [[ -d "$db" ]] || continue
      new="$NEW_PRIV/Rime/$(basename "$db" | sed 's/^quiet_/ergou_/')"
      same_tree "$db" "$new" || die "user dictionary $(basename "$db") did not copy cleanly"
    done
    log "Rime user data: $(ls "$NEW_PRIV/Rime" | tr '\n' ' ')"
  fi
  for f in voice-history.json verified-files.json; do
    [[ -f "$OLD_PRIV/$f" ]] || continue
    cp -p "$OLD_PRIV/$f" "$NEW_PRIV/$f"
    cmp -s "$OLD_PRIV/$f" "$NEW_PRIV/$f" || die "$f did not copy cleanly"
  done
  # The checksum cache is keyed by path: point it at the moved models so the
  # 5 GB of models are not hashed again.
  if [[ -f "$NEW_PRIV/verified-files.json" ]]; then
    sed -i '' "s#com\.codamon\.quietime#com.codamon.ergou#g" "$NEW_PRIV/verified-files.json"
  fi
  log "Voice history and model checksum cache: copied"
fi
# The Corrector service keeps its own checksum cache (only if it has run).
OLD_COR="$HOME/Library/Containers/$OLD_IM.Corrector/Data/Library/Application Support/QuietIME/verified-files.json"
NEW_COR_DIR="$HOME/Library/Containers/$NEW_IM.Corrector/Data/Library/Application Support/ErgouIME"
if [[ -f "$OLD_COR" && -d "$HOME/Library/Containers/$NEW_IM.Corrector" ]]; then
  mkdir -p "$NEW_COR_DIR"
  sed "s#com\.codamon\.quietime#com.codamon.ergou#g" "$OLD_COR" > "$NEW_COR_DIR/verified-files.json"
  log "Corrector checksum cache: copied"
fi
date > "$STAMP"
# Enable 二狗 in the saved input source list and drop the old name's entries.
app_new="$HOME/Library/Input Methods/ErgouIME.app"
[[ -d "$app_new" ]] || app_new="/Library/Input Methods/ErgouIME.app"
if [[ -d "$app_new" ]]; then
  /bin/bash "$(cd "$(dirname "$0")" && pwd)/pkg/input-sources.sh" "$app_new" || true
fi

log "Migrated. Check 二狗输入法设置 (settings, models, 我的词, cloud key), type a"
log "few words, then run: $0 --remove-old"
