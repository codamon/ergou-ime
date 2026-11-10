#!/usr/bin/env bash
# ergou-ime — build (Debug) and install into ~/Library/Input Methods.
# SPDX-License-Identifier: GPL-3.0-only
#
#   ./scripts/install.sh                 build with xcodebuild, then install
#   ./scripts/install.sh path/to/ErgouIME.app   install an already built app
#
# ErgouIME Settings is inside the bundle (Contents/Library/LoginItems), so
# installing ErgouIME.app installs both.
#
# First install: macOS may only list the new input source after you log out
# and back in. Then add it in System Settings → Keyboard → Input Sources
# (it appears under Chinese, Simplified as "二狗输入法").
# Debug builds only the active architecture; use -configuration Release for
# a Universal (arm64 + x86_64) build.
source "$(dirname "$0")/lib/common.sh"
require_macos

app="${1:-}"
if [[ -z "$app" ]]; then
  require_cmd xcodebuild
  [[ -d "$REPO_ROOT/ErgouIME.xcodeproj" ]] || die "run ./scripts/bootstrap.sh first"
  log "Building (Debug)"
  xcodebuild -project "$REPO_ROOT/ErgouIME.xcodeproj" -target ErgouIME \
    -configuration Debug SYMROOT="$REPO_ROOT/build" -quiet build
  app="$REPO_ROOT/build/Debug/ErgouIME.app"
fi
[[ -d "$app" ]] || die "app not found: $app"

# Prefer an existing system-wide copy owned by this user (set up once with
# sudo; see docs/PLAN-v1.md), otherwise install per user.
system="/Library/Input Methods/ErgouIME.app"
if [[ -d "$system" && -O "$system" ]]; then
  dest="$system"
else
  dest="$HOME/Library/Input Methods/ErgouIME.app"
fi
pkill -x ErgouIME 2>/dev/null || true
pkill -f "ErgouIME Settings.app/Contents/MacOS/" 2>/dev/null || true
mkdir -p "$(dirname "$dest")"
# rsync into the bundle (works for the user-owned system copy without sudo).
rsync -a --delete "$app/" "$dest/"
log "Installed → $dest"

# Sandboxed apps (WeChat, QQ, Notes, …) keep their own input source table in
# $DARWIN_USER_CACHE_DIR/<bundle id>/com.apple.IntlDataCache.le*. A table
# written before this input method was installed never learns about it, and
# switching to it there crashes the app inside Apple's
# -[TUINSCursorUIController _selectCurrentInputSource] (CFRelease(NULL)).
# Delete tables that do not point at this install BEFORE registering; registration then
# makes running apps reload and rebuild them. Same fix as qingjian PR #421 /
# xsime issue #90. These are caches; apps rebuild them.
cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
if [[ -n "$cache" && -d "$cache" ]]; then
  cleared=0
  while IFS= read -r f; do
    # Rebuild every table that does not point at the current install, and
    # every table that mentions us at all: those may hold our old name or
    # icon (the switcher showed the raw mode ID after an update).
    if ! strings -a "$f" 2>/dev/null | grep -qF "${dest%.app}" \
       || strings -a "$f" 2>/dev/null | grep -qF "com.codamon.inputmethod.Ergou"; then
      rm -f "${f%.kbdx}" "$f" && cleared=$((cleared + 1))
    fi
  done < <(find "$cache" -mindepth 2 -maxdepth 2 -name 'com.apple.IntlDataCache.le.kbdx' 2>/dev/null)
  log "Cleared $cleared stale input source caches"
fi

"$dest/Contents/MacOS/ErgouIME" --register-input-source || warn "register failed"
"$dest/Contents/MacOS/ErgouIME" --enable-input-source \
  || warn "not enabled yet — log out and back in, then run this script again or add it in System Settings"
# Make sure the user's saved list has it too (otherwise it is greyed out in
# the input menu), and reload the menu.
"$REPO_ROOT/scripts/pkg/input-sources.sh" "$dest" || true
