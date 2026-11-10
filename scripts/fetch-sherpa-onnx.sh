#!/usr/bin/env bash
# ergou-ime — download prebuilt sherpa-onnx (shared, no TTS, universal2).
# SPDX-License-Identifier: GPL-3.0-only
#
# sherpa-onnx is Apache-2.0 (https://github.com/k2-fsa/sherpa-onnx); it bundles
# onnxruntime (MIT). We use the C API only.
source "$(dirname "$0")/lib/common.sh"
require_macos

SHERPA_VERSION="2.0.1"
SHERPA_NAME="sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-shared-no-tts"
SHERPA_SHA256="9021b6f33e8d1657fe5ae7a13e83fc948707f86b749dc7b775680db6451cc2b8"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${SHERPA_NAME}.tar.bz2"

archive="$(download_verified "$URL" "$SHERPA_SHA256")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tar -xjf "$archive" -C "$work"

dest="$VENDOR_DIR/sherpa-onnx"
rm -rf "$dest"; mkdir -p "$dest/lib"
cp -R "$work/$SHERPA_NAME/include" "$dest/"
cp "$work/$SHERPA_NAME/lib/libsherpa-onnx-c-api.dylib" \
   "$work/$SHERPA_NAME/lib/libonnxruntime.dylib" "$dest/lib/"

# Install names are already @rpath/… in the official build.
log "sherpa-onnx $SHERPA_VERSION → $dest"
