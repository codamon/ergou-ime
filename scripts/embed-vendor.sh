#!/usr/bin/env bash
# ergou-ime — Xcode "Run Script" build phase (wired up in project.yml).
# SPDX-License-Identifier: GPL-3.0-only
#
# Copies optional vendor dylibs into ErgouIME.app/Contents/Frameworks (librime's
# Lua plugin into Frameworks/rime-plugins, where librime looks for plugins),
# Rime data into Contents/SharedSupport/rime-data — the vendor schemas and
# dictionaries, then our own RimeData/ (ergou_wubi, ergou_pinyin, lua/ergou)
# on top — and re-signs the dylibs with the app's identity. Does nothing for
# parts that are not present in vendor/.
# Speech models are never bundled (see fetch-sensevoice-model.sh).
set -euo pipefail

: "${SRCROOT:?run from Xcode}" "${TARGET_BUILD_DIR:?}" "${FRAMEWORKS_FOLDER_PATH:?}" "${SHARED_SUPPORT_FOLDER_PATH:?}"
vendor="$SRCROOT/vendor"
frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
shared="$TARGET_BUILD_DIR/$SHARED_SUPPORT_FOLDER_PATH"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[[ -n "$identity" ]] || identity="-"

embed_dylib() { # src [subdir of Frameworks]
  local src="$1" dir="$frameworks${2:+/$2}"
  [[ -f "$src" ]] || return 0
  mkdir -p "$dir"
  # Copy the real file under the name the binary links against.
  cp -fL "$src" "$dir/$(basename "$src")"
  # OTHER_CODE_SIGN_FLAGS may carry --keychain (signing from SSH, see
  # scripts/build-signed.sh); pass it on so the dylibs use the same keychain.
  # shellcheck disable=SC2086
  codesign --force --sign "$identity" --timestamp=none --options runtime ${OTHER_CODE_SIGN_FLAGS:-} "$dir/$(basename "$src")"
  echo "embedded ${2:+$2/}$(basename "$src")"
}

embed_dylib "$vendor/librime/lib/librime.1.dylib"
# librime loads every dylib in <dir of librime.1.dylib>/rime-plugins.
embed_dylib "$vendor/librime/lib/rime-plugins/librime-lua.dylib" rime-plugins
embed_dylib "$vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib"
embed_dylib "$vendor/sherpa-onnx/lib/libonnxruntime.dylib"

if [[ -d "$vendor/rime-data" ]]; then
  mkdir -p "$shared"
  rsync -a --delete "$vendor/rime-data/" "$shared/rime-data/"
  # Our schemas and Lua scripts (ergou_wubi, ergou_pinyin, lua/ergou).
  rsync -a "$SRCROOT/RimeData/" "$shared/rime-data/"
  # OpenCC data for 简 → 繁 (librime looks in <shared>/opencc).
  if [[ -d "$vendor/librime/opencc" ]]; then
    rsync -a "$vendor/librime/opencc/" "$shared/rime-data/opencc/"
  fi
  echo "embedded rime-data"
fi

# 联想 database (scripts/fetch-predict.sh): read-only, in SharedSupport.
if [[ -f "$vendor/predict/predict.sqlite" ]]; then
  mkdir -p "$shared"
  cp -f "$vendor/predict/predict.sqlite" "$shared/predict.sqlite"
  echo "embedded predict.sqlite"
fi

# Licence texts of everything bundled (docs/licenses/README.md), plus our own.
licenses="$TARGET_BUILD_DIR/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-Contents/Resources}/Licenses"
mkdir -p "$licenses"
cp -f "$SRCROOT/LICENSE" "$licenses/ergou-ime-GPL-3.0.txt"
find "$SRCROOT/docs/licenses" -maxdepth 1 -name '*.txt' -exec cp -f {} "$licenses/" \;
[[ -f "$vendor/llama/LICENSE" ]] && cp -f "$vendor/llama/LICENSE" "$licenses/llama.cpp.txt"
echo "embedded licences"
