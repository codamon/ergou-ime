#!/usr/bin/env bash
# ergou-ime — download prebuilt librime (macOS universal) into vendor/librime.
# SPDX-License-Identifier: GPL-3.0-only
#
# librime is BSD-3-Clause (https://github.com/rime/librime). We use the
# official CI release build. Of its plugins only librime-lua is copied (mixed
# wubi + pinyin input, discussion §3.5); octagram and predict are not used.
source "$(dirname "$0")/lib/common.sh"
require_macos

LIBRIME_VERSION="1.17.0"
LIBRIME_ASSET="rime-33e7814-macOS-universal.tar.bz2"
LIBRIME_SHA256="11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850"
# The same release's dependency bundle carries OpenCC's data (Apache-2.0),
# used for 简 → 繁 (s2t). Only that data is taken from it.
DEPS_ASSET="rime-deps-33e7814-macOS-universal.tar.bz2"
DEPS_SHA256="dfe6047e87be271963d7466bd1a6e3d9e660c30e5e73e4bb94e8782c0a6ac8df"
URL="https://github.com/rime/librime/releases/download/$LIBRIME_VERSION/$LIBRIME_ASSET"

archive="$(download_verified "$URL" "$LIBRIME_SHA256")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tar -xjf "$archive" -C "$work"

dest="$VENDOR_DIR/librime"
rm -rf "$dest"
mkdir -p "$dest/include" "$dest/lib"
cp "$work"/dist/include/*.h "$dest/include/"
cp -P "$work"/dist/lib/librime*.dylib "$dest/lib/"
mkdir -p "$dest/lib/rime-plugins"
cp "$work"/dist/lib/rime-plugins/librime-lua.dylib "$dest/lib/rime-plugins/"
[[ -f "$work/dist/version-info.txt" ]] && cp "$work/dist/version-info.txt" "$dest/"

deps="$(download_verified "https://github.com/rime/librime/releases/download/$LIBRIME_VERSION/$DEPS_ASSET" "$DEPS_SHA256")"
mkdir -p "$work/deps" "$dest/opencc"
tar -xjf "$deps" -C "$work/deps" share/opencc
cp "$work"/deps/share/opencc/{s2t.json,STPhrases.ocd2,STCharacters.ocd2} "$dest/opencc/"

# Install name is already @rpath/librime.1.dylib in the official build.
log "librime $LIBRIME_VERSION → $dest"
otool -D "$dest/lib/librime.1.dylib" | tail -n1
otool -L "$dest/lib/rime-plugins/librime-lua.dylib" | sed -n 2,4p  # expect @rpath/librime.1.dylib
