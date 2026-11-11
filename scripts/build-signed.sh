#!/usr/bin/env bash
# ergou-ime — signed build (Release by default) + install, usable from an SSH session.
# SPDX-License-Identifier: GPL-3.0-only
#
# Needs a one-time setup on the Mac (in Terminal, not over SSH) that copies the
# signing identities into their own keychain (paths: load_signing_env in
# scripts/lib/common.sh). The login keychain is locked in SSH sessions, so
# signing from it fails with errSecInternalComponent.
#
# Signs with the Developer ID Application identity when the keychain has it
# (same identity as releases, so TCC grants such as microphone and input
# monitoring survive switching between dev and release builds); falls back to
# Apple Development otherwise.
#
#   ./scripts/build-signed.sh            Release build + install into ~/Library/Input Methods
#   ./scripts/build-signed.sh --no-install
#   ERGOU_CONFIG=Debug ./scripts/build-signed.sh
#
# For a Developer ID build, .pkg and notarisation use scripts/release.sh.
source "$(dirname "$0")/lib/common.sh"
require_macos
install=1; [[ "${1:-}" == "--no-install" ]] && install=0
load_signing_env
team="$(team_id)"
kc="$ERGOU_SIGNING_KEYCHAIN"
unlock_signing_keychain

derived="${ERGOU_DERIVED_DATA:-$REPO_ROOT/build/signed}"
config="${ERGOU_CONFIG:-Release}"
identity="$(security find-identity -v -p codesigning "$kc" \
  | sed -n "s/.*\"\(Developer ID Application: .*($team)\)\"/\1/p" | head -1)"
if [[ -z "$identity" ]]; then
  identity="Apple Development"
  warn "no Developer ID Application identity for team $team in $kc; using Apple Development (TCC grants will not carry over to release builds)"
fi
log "Building signed $config (team $team, identity: $identity)"
xcodebuild -project "$REPO_ROOT/ErgouIME.xcodeproj" -scheme ErgouIME -configuration "$config" \
  -derivedDataPath "$derived" \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" DEVELOPMENT_TEAM="$team" \
  PROVISIONING_PROFILE_SPECIFIER= "OTHER_CODE_SIGN_FLAGS=--keychain $kc" \
  -quiet build
app="$derived/Build/Products/$config/ErgouIME.app"
codesign --verify --deep --strict "$app"
log "Signed: $app"
(( install )) && "$REPO_ROOT/scripts/install.sh" "$app"

# The build products share the installed app's bundle IDs. If Launch Services
# knows them, "Quit & Reopen" after a permission prompt can relaunch a build
# copy instead of the installed input method (seen 2026-11-10: the menu lost
# its items). Keep only the installed copy registered.
if (( install )); then
  find "$derived/Build/Products" -maxdepth 2 -name "*.app" -type d -exec "$lsregister" -u {} \; 2>/dev/null || true
  "$lsregister" -u "$app/Contents/Library/LoginItems/ErgouIME Settings.app" 2>/dev/null || true
fi
