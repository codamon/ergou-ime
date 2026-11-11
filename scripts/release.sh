#!/usr/bin/env bash
# ergou-ime — release build: Developer ID signature, .pkg, notarisation.
# SPDX-License-Identifier: GPL-3.0-only
#
#   ./scripts/release.sh                 build, sign, package, notarise, staple
#   ./scripts/release.sh --no-notarize   stop after the signed .pkg (for testing)
#   ./scripts/release.sh --notarize-only [SUBMISSION-ID]
#                                        notarise the existing build/release pkg, or
#                                        wait for an earlier submission (Apple can
#                                        take hours for a new developer account)
#
# Needs on the Mac (see load_signing_env in scripts/lib/common.sh):
#   - a keychain with "Developer ID Application: <name> (<TeamID>)" and
#     "Developer ID Installer: <name> (<TeamID>)";
#   - a notarytool profile stored in that keychain:
#       xcrun notarytool store-credentials <profile> --keychain <keychain> …
#   - Config/Local.xcconfig with ERGOU_TEAM_ID (scripts/configure.sh) and the
#     vendor/ dependencies (scripts/bootstrap.sh --all, scripts/fetch-*.sh).
#
# Output in build/release/:
#   ErgouIME-<version>.pkg, .pkg.sha256, notary-submit.json, notary-log.json,
#   ErgouIME.app (the signed app that went into the package).
#
# The package installs for the current user only (~/Library/Input Methods);
# its postinstall quits the old process, clears stale input source caches and
# registers the input source (scripts/pkg/postinstall). Uninstall:
# scripts/uninstall.sh.
source "$(dirname "$0")/lib/common.sh"
require_macos
require_cmd xcodebuild
notarize=1 only=0 id=""
case "${1:-}" in
  --no-notarize) notarize=0 ;;
  --notarize-only) only=1; id="${2:-}" ;;
esac

load_signing_env
team="$(team_id)"
kc="$ERGOU_SIGNING_KEYCHAIN"
unlock_signing_keychain

version="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\} *$/\1/p' "$REPO_ROOT/project.yml" | head -1)"
[[ -n "$version" ]] || die "no MARKETING_VERSION in project.yml"

# Every model/dictionary download must still match its fixed SHA-256 at the
# source (a publisher re-uploading a file breaks it for all users). Set
# ERGOU_SKIP_MODEL_CHECK=1 only when offline on purpose.
if (( ! only )) && [[ "${ERGOU_SKIP_MODEL_CHECK:-}" != 1 ]]; then
  log "Checking model downloads at their sources"
  python3 "$REPO_ROOT/scripts/check-model-urls.py" || die "a model download changed or is gone (scripts/check-model-urls.py)"
fi

find_identity() {
  security find-identity -v -p "$2" "$kc" | sed -n "s/.*\"\($1: .*($team)\)\"/\1/p" | head -1
}
app_identity="$(find_identity "Developer ID Application" codesigning)"
pkg_identity="$(find_identity "Developer ID Installer" basic)"
[[ -n "$app_identity" ]] || die "no Developer ID Application identity for team $team in $kc"
[[ -n "$pkg_identity" ]] || die "no Developer ID Installer identity for team $team in $kc"

out="$REPO_ROOT/build/release"
derived="$out/DerivedData"
pkg="$out/ErgouIME-$version.pkg"
if (( only )); then
  [[ -f "$pkg" ]] || die "no $pkg; run without --notarize-only first"
else
rm -rf "$out/ErgouIME.app" "$out/pkgroot" "$out/pkgscripts" "$out"/*.pkg "$out"/*.sha256 "$out"/notary-*.json
mkdir -p "$out"

# ---------------------------------------------------------------- build
log "Building Release $version (Developer ID, team $team)"
xcodebuild -project "$REPO_ROOT/ErgouIME.xcodeproj" -scheme ErgouIME -configuration Release \
  -derivedDataPath "$derived" -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$app_identity" DEVELOPMENT_TEAM="$team" \
  PROVISIONING_PROFILE_SPECIFIER= "OTHER_CODE_SIGN_FLAGS=--keychain $kc --timestamp" \
  -quiet clean build
built="$derived/Build/Products/Release/ErgouIME.app"
[[ -d "$built" ]] || die "build product missing: $built"
# Keep Launch Services from knowing the build products (same bundle IDs as
# the installed app; see scripts/build-signed.sh).
find "$derived/Build/Products" -maxdepth 4 -name "*.app" -type d -exec "$lsregister" -u {} \; 2>/dev/null || true
ditto "$built" "$out/ErgouIME.app"
app="$out/ErgouIME.app"

# ---------------------------------------------------------------- sign
# Re-sign everything from the inside out with a secure timestamp and the
# hardened runtime. Entitlements are taken from Xcode's signature (build
# settings such as the App Group are already expanded there), so the
# sandbox entitlements stay exactly what the .entitlements files say.
ents_of() {
  local f="$out/ents-$(basename "$1").plist"
  codesign -d --entitlements - --xml "$1" > "$f" 2>/dev/null || true
  # Debug-only entitlement; notarisation refuses it.
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$f" >/dev/null 2>&1 || true
  printf '%s\n' "$f"
}
sign() {   # sign PATH [ENTITLEMENTS]
  local extra=()
  [[ -n "${2:-}" && -s "$2" ]] && extra=(--entitlements "$2")
  codesign --force --timestamp --options runtime --keychain "$kc" --sign "$app_identity" ${extra[@]+"${extra[@]}"} "$1"
}

log "Signing nested code"
while IFS= read -r lib; do sign "$lib"; done < <(find "$app/Contents" -type f \( -name '*.dylib' -o -name '*.so' \) | sort)
for xpc in "$app"/Contents/XPCServices/*.xpc; do
  [[ -d "$xpc" ]] || continue
  sign "$xpc" "$(ents_of "$xpc")"
done
settings="$app/Contents/Library/LoginItems/ErgouIME Settings.app"
[[ -d "$settings" ]] || die "Settings app missing: $settings"
sign "$settings" "$(ents_of "$settings")"
sign "$app" "$(ents_of "$app")"
rm -f "$out"/ents-*.plist

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$app"
info="$(codesign -dvv "$app" 2>&1)"
[[ $(grep -cE '^(Authority=Developer ID Application|Timestamp=|Runtime Version=)' <<<"$info") -eq 3 ]] \
  || die "app is not signed with Developer ID + timestamp + hardened runtime"
while IFS= read -r bin; do
  [[ "$(file -b "$bin")" == Mach-O* ]] || continue
  info="$(codesign -dvv "$bin" 2>&1)"
  grep -q '^Timestamp=' <<<"$info" || die "no secure timestamp: $bin"
  grep -q '^Authority=Developer ID Application' <<<"$info" || die "not signed with Developer ID: $bin"
  archs="$(lipo -archs "$bin")"
  # Metal backend of llama.cpp is Apple-silicon only upstream.
  [[ "$archs" == *x86_64* && "$archs" == *arm64* || "$bin" == *libggml-metal* ]] || die "not universal ($archs): $bin"
done < <(find "$app/Contents" -type f \( -perm -u+x -o -name '*.dylib' \))
"$REPO_ROOT/scripts/check-no-network.sh" "$app"

# ---------------------------------------------------------------- package
log "Building the installer package"
mkdir -p "$out/pkgroot"
ditto "$app" "$out/pkgroot/ErgouIME.app"
mkdir -p "$out/pkgscripts"
cp "$REPO_ROOT/scripts/pkg/preinstall" "$REPO_ROOT/scripts/pkg/postinstall" "$REPO_ROOT/scripts/pkg/input-sources.sh" "$out/pkgscripts/"
chmod 755 "$out/pkgscripts/"*
components="$out/components.plist"
pkgbuild --analyze --root "$out/pkgroot" "$components" >/dev/null
# Install exactly where we say; never "upgrade" a copy found elsewhere (for
# example a build product with the same bundle ID).
/usr/libexec/PlistBuddy -c 'Delete :0:BundleIsRelocatable' "$components" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$components"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$components"
pkgbuild --root "$out/pkgroot" --component-plist "$components" \
  --identifier com.codamon.inputmethod.Ergou.pkg --version "$version" \
  --install-location "/Library/Input Methods" --scripts "$out/pkgscripts" \
  "$out/ErgouIME-component.pkg" >/dev/null

sed -e "s/@VERSION@/$version/g" "$REPO_ROOT/scripts/pkg/Distribution.xml" > "$out/Distribution.xml"
productbuild --distribution "$out/Distribution.xml" --package-path "$out" \
  --resources "$REPO_ROOT/scripts/pkg/resources" \
  --sign "$pkg_identity" --keychain "$kc" --timestamp "$pkg" >/dev/null
# Copies of the app outside ~/Library/Input Methods share its bundle ID;
# if Launch Services or Text Input Sources keep them, the input source can
# appear twice and show greyed out (D's Mac, 2026-11-10). Unregister and
# remove every staging copy; only the .pkg is kept.
for staged in "$out/pkgroot/ErgouIME.app" "$out/ErgouIME.app" "$derived/Build/Products/Release/ErgouIME.app"; do
  [[ -d "$staged" ]] || continue
  find "$staged" -name "*.app" -type d -exec "$lsregister" -u {} \; 2>/dev/null || true
done
rm -rf "$out/pkgroot" "$out/pkgscripts" "$out/ErgouIME-component.pkg" "$components" "$out/Distribution.xml"
rm -rf "$out/ErgouIME.app" "$derived/Build/Products"
pkgutil --check-signature "$pkg" | grep -q 'Developer ID Installer' || die "package not signed with Developer ID Installer"
log "Package: $pkg"
fi

# ---------------------------------------------------------------- notarise
if (( notarize )); then
  log "Notarising (this waits for Apple)"
  if [[ -n "$id" ]]; then
    xcrun notarytool wait "$id" --keychain-profile "$ERGOU_NOTARY_PROFILE" --keychain "$kc" \
      --output-format json > "$out/notary-submit.json" || true
  else
    xcrun notarytool submit "$pkg" --keychain-profile "$ERGOU_NOTARY_PROFILE" --keychain "$kc" \
      --wait --output-format json > "$out/notary-submit.json" || true
  fi
  id="$(plutil -extract id raw -o - "$out/notary-submit.json" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$out/notary-submit.json" 2>/dev/null || true)"
  [[ -n "$id" ]] || die "notarytool submit failed: $(cat "$out/notary-submit.json")"
  xcrun notarytool log "$id" --keychain-profile "$ERGOU_NOTARY_PROFILE" --keychain "$kc" "$out/notary-log.json" >/dev/null || true
  [[ "$status" == "Accepted" ]] || die "notarisation $status (see $out/notary-log.json)"
  xcrun stapler staple "$pkg"
  xcrun stapler validate "$pkg"
  spctl -a -vvv -t install "$pkg" 2>&1 | tee "$out/spctl.txt"
  grep -q 'accepted' "$out/spctl.txt" || die "Gatekeeper does not accept the package"
  grep -q 'Notarized Developer ID' "$out/spctl.txt" || die "Gatekeeper does not see the notarisation"
fi

(cd "$out" && shasum -a 256 "$(basename "$pkg")" > "$(basename "$pkg").sha256")
log "SHA-256: $(cut -d' ' -f1 "$pkg.sha256")"
log "Size: $(du -h "$pkg" | cut -f1)"
