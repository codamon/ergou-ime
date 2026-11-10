#!/usr/bin/env bash
# ergou-ime — copy llama.cpp dylibs into ErgouIMECorrector.xpc/Contents/Frameworks
# and sign them (Xcode build phase of the ErgouIMECorrector target).
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
: "${SRCROOT:?run from Xcode}" "${TARGET_BUILD_DIR:?}" "${FRAMEWORKS_FOLDER_PATH:?}"
src="$SRCROOT/vendor/llama/lib"
[[ -d "$src" ]] || exit 0
dest="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"; [[ -n "$identity" ]] || identity="-"
mkdir -p "$dest"
for lib in "$src"/*.0.dylib; do
  cp -fL "$lib" "$dest/"
  # shellcheck disable=SC2086
  codesign --force --sign "$identity" --timestamp=none --options runtime ${OTHER_CODE_SIGN_FLAGS:-} "$dest/$(basename "$lib")"
done
echo "embedded llama.cpp ($(ls "$src"/*.0.dylib | wc -l | tr -d ' ') dylibs)"
