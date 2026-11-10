#!/usr/bin/env bash
# ergou-ime — fetch Rime schema data into vendor/rime-data.
# SPDX-License-Identifier: GPL-3.0-only
#
#   rime-prelude         LGPL-3.0  default.yaml, key_bindings, punctuation, symbols
#   rime-wubi86-jidian   MIT       五笔 86 极点码表 schema + dictionaries
#
# Pinned to commits; bump deliberately. The files are bundled into the app at
# ErgouIME.app/Contents/SharedSupport/rime-data by scripts/embed-vendor.sh.
source "$(dirname "$0")/lib/common.sh"
require_macos
require_cmd git

PRELUDE_REPO="https://github.com/rime/rime-prelude.git"
PRELUDE_COMMIT="082425ea0684bca36474415d4a0e8db9b016487e"
JIDIAN_REPO="https://github.com/KyleBing/rime-wubi86-jidian.git"
JIDIAN_COMMIT="4d08110b8080f6577dad733ada7e5ae5c5e878fd"

checkout() { # repo commit dir
  local repo="$1" commit="$2" dir="$3"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet --filter=blob:none "$repo" "$dir"
  fi
  git -C "$dir" fetch --quiet origin "$commit" 2>/dev/null || git -C "$dir" fetch --quiet origin
  git -C "$dir" -c advice.detachedHead=false checkout --quiet "$commit"
}

src="$VENDOR_DIR/src"
mkdir -p "$src"
log "rime-prelude @ ${PRELUDE_COMMIT:0:7}"
checkout "$PRELUDE_REPO" "$PRELUDE_COMMIT" "$src/rime-prelude"
log "rime-wubi86-jidian @ ${JIDIAN_COMMIT:0:7}"
checkout "$JIDIAN_REPO" "$JIDIAN_COMMIT" "$src/rime-wubi86-jidian"

dest="$VENDOR_DIR/rime-data"
rm -rf "$dest"; mkdir -p "$dest"
cp "$src"/rime-prelude/*.yaml "$dest/"
# Schemas and dictionaries only. Frontend-specific customisations
# (squirrel/weasel/default.custom.yaml) are left out; ErgouIME generates its
# own custom files (ErgouIME/Engine/RimeUserConfig.swift). Our schemas and Lua
# scripts live in RimeData/ and are bundled by scripts/embed-vendor.sh.
find "$src/rime-wubi86-jidian" -maxdepth 1 -type f \
  \( -name '*.schema.yaml' -o -name '*.dict.yaml' \) -exec cp {} "$dest/" \;
cp "$src/rime-prelude/LICENSE" "$dest/LICENSE.rime-prelude"
cp "$src/rime-wubi86-jidian/LICENSE" "$dest/LICENSE.rime-wubi86-jidian"

log "Rime data → $dest ($(ls "$dest" | wc -l | tr -d ' ') files)"
