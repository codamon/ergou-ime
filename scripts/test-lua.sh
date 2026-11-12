#!/usr/bin/env bash
# ergou-ime — run the Lua unit tests (librime-lua globals are mocked).
# SPDX-License-Identifier: GPL-3.0-only
#
# Uses lua5.4 / lua if installed, otherwise an alpine container.
# These tests only cover our own logic; the real librime-lua API still has to
# be checked on a Mac (docs/PLAN-v1.md M1.5).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
run() { ERGOU_LUA_DIR="$root/RimeData/lua" "$1" "$root/tests/lua/test_pinyin.lua" && ERGOU_LUA_DIR="$root/RimeData/lua" "$1" "$root/tests/lua/test_components.lua" && ERGOU_LUA_DIR="$root/RimeData/lua" "$1" "$root/tests/lua/test_calc.lua" && ERGOU_LUA_DIR="$root/RimeData/lua" "$1" "$root/tests/lua/test_english.lua" && ERGOU_LUA_DIR="$root/RimeData/lua" "$1" "$root/tests/lua/test_select_character.lua"; }
for bin in lua5.4 lua; do
  if command -v "$bin" >/dev/null; then run "$bin"; exit; fi
done
docker run --rm -v "$root:/src:ro" -w /src alpine:latest sh -c \
  'apk add -q --no-progress lua5.4 >/dev/null && ERGOU_LUA_DIR=/src/RimeData/lua lua5.4 tests/lua/test_pinyin.lua && ERGOU_LUA_DIR=/src/RimeData/lua lua5.4 tests/lua/test_components.lua && ERGOU_LUA_DIR=/src/RimeData/lua lua5.4 tests/lua/test_calc.lua && ERGOU_LUA_DIR=/src/RimeData/lua lua5.4 tests/lua/test_english.lua && ERGOU_LUA_DIR=/src/RimeData/lua lua5.4 tests/lua/test_select_character.lua'
