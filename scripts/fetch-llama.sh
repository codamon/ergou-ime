#!/usr/bin/env bash
# ergou-ime — prebuilt llama.cpp (MIT) for the voice-correction XPC service.
# SPDX-License-Identifier: GPL-3.0-only
#
# Official release b12211: the arm64 and x64 macOS builds are merged with lipo
# into universal dylibs in vendor/llama/lib; headers come from the same tag.
# Only libllama + libggml* are used (no server, no CLI). libggml-rpc is a
# link-time dependency of libllama; its remote backend is never used and the
# XPC service has no network entitlement.
source "$(dirname "$0")/lib/common.sh"
require_macos
require_cmd lipo

TAG="b12211"
ARM_SHA="4da4edb437358d31d55938ad849d262ca31b0e0ffb35e9caedb727a0cd5a8f0f"
X64_SHA="6055cc672cc5c744481bb88ac1a7739ff476966c8a190ddaa20676034693a358"
BASE="https://github.com/ggml-org/llama.cpp/releases/download/$TAG"
RAW="https://raw.githubusercontent.com/ggml-org/llama.cpp/$TAG"

arm="$(download_verified "$BASE/llama-$TAG-bin-macos-arm64.tar.gz" "$ARM_SHA")"
x64="$(download_verified "$BASE/llama-$TAG-bin-macos-x64.tar.gz" "$X64_SHA")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/arm" "$work/x64"
tar -xzf "$arm" -C "$work/arm"
tar -xzf "$x64" -C "$work/x64"
arm_dir="$(dirname "$(find "$work/arm" -name 'libllama.0.dylib' -print -quit)")"
x64_dir="$(dirname "$(find "$work/x64" -name 'libllama.0.dylib' -print -quit)")"

dest="$VENDOR_DIR/llama"
rm -rf "$dest"; mkdir -p "$dest/lib" "$dest/include"
# The binary links against the .0 names (install names are @rpath/lib*.0.dylib).
for lib in libllama.0.dylib libggml.0.dylib libggml-base.0.dylib libggml-cpu.0.dylib \
           libggml-metal.0.dylib libggml-blas.0.dylib libggml-rpc.0.dylib; do
  if [[ -f "$x64_dir/$lib" ]]; then
    lipo -create "$(realpath "$arm_dir/$lib")" "$(realpath "$x64_dir/$lib")" -output "$dest/lib/$lib"
  else
    cp "$(realpath "$arm_dir/$lib")" "$dest/lib/$lib"   # e.g. Metal is arm64-only
  fi
done
ln -sf libllama.0.dylib "$dest/lib/libllama.dylib"
for h in include/llama.h ggml/include/ggml.h ggml/include/ggml-backend.h ggml/include/ggml-alloc.h \
         ggml/include/ggml-cpu.h ggml/include/gguf.h ggml/include/ggml-opt.h; do
  curl -fsSL "$RAW/$h" -o "$dest/include/$(basename "$h")"
done
cp "$arm_dir/LICENSE" "$dest/LICENSE" 2>/dev/null || curl -fsSL "$RAW/LICENSE" -o "$dest/LICENSE"
log "llama.cpp $TAG → $dest"
for lib in "$dest"/lib/*.0.dylib; do printf '  %s: %s\n' "$(basename "$lib")" "$(lipo -archs "$lib")"; done
otool -L "$dest/lib/libllama.0.dylib" | sed -n 2,6p
