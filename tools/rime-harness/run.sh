#!/usr/bin/env bash
# ergou-ime — drive librime + our schemas from the command line (macOS).
# SPDX-License-Identifier: GPL-3.0-only
#
# Builds tools/rime-harness/harness against vendor/librime, writes a Rime user
# dir like RimeUserConfig would, and types the given key sequences.
#   ./tools/rime-harness/run.sh [--auto] [--strict] [--pinyin] [--dict DIR] keys...
#   --dict DIR: use 拼音大词库 from DIR (holding cn_dicts/*.dict.yaml), as
#   PinyinDictionary.swift does after the download; default: pinyin_simp.
#   --tencent: with --dict, also import cn_dicts/tencent (腾讯词库).
#   keys: letters as typed; "_" = Space. Example: run.sh --auto trntkhlg shang
# Needs a Debug build (for the bundled rime-data) and scripts/fetch-librime.sh.
# No input method is installed and no system setting is touched.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; root="$(cd "$here/../.." && pwd)"
auto=false strict=false schema=ergou_wubi dict="" tencent=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in --auto) auto=true ;; --strict) strict=true ;; --pinyin) schema=ergou_pinyin_ime ;;
    --dict) dict="$2"; shift ;; --tencent) tencent=true ;; *) echo "unknown $1" >&2; exit 2 ;; esac; shift
done
lib="$root/vendor/librime"
shared="${ERGOU_RIME_DATA:-$(find "$root/../dd" "$HOME/Library/Developer/Xcode/DerivedData" -path '*Debug/ErgouIME.app/Contents/SharedSupport/rime-data' -maxdepth 8 2>/dev/null | head -1)}"
[[ -d "$shared" ]] || { echo "rime-data not found; build Debug or set ERGOU_RIME_DATA" >&2; exit 1; }
rsync -a "$root/RimeData/" "$shared/"   # pick up edits without rebuilding
bin="$here/.build/harness"; mkdir -p "$here/.build"
clang -o "$bin" "$here/harness.c" -I"$lib/include" -L"$lib/lib" -lrime -Wl,-rpath,"$lib/lib"
user="$here/.build/user-$auto-$strict-$schema${dict:+-dict}-$tencent"; rm -rf "$user"; mkdir -p "$user"
if [[ -n "$dict" ]]; then
  mkdir -p "$user/cn_dicts"
  cp "$dict"/cn_dicts/{8105,base,ext}.dict.yaml "$user/cn_dicts/"
  extra=""; $tencent && { cp "$dict/cn_dicts/tencent.dict.yaml" "$user/cn_dicts/"; extra='  - cn_dicts/tencent\n'; }
  printf -- "---\nname: ergou_pinyin_dict\nversion: \"rime-ice-2026.06.30\"\nsort: by_weight\nimport_tables:\n  - cn_dicts/8105\n  - cn_dicts/base\n  - cn_dicts/ext\n${extra}...\n" > "$user/ergou_pinyin_dict.dict.yaml"
fi
printf 'patch:\n  schema_list:\n    - schema: %s\n  menu/page_size: 5\n' "$schema" > "$user/default.custom.yaml"
cat > "$user/ergou_wubi.custom.yaml" <<Y
patch:
  translator/enable_user_dict: true
  pinyin/enable_user_dict: true
  pinyin/enable_correction: false
  pinyin_only/enable_correction: true
  ergou/auto_commit: $auto
  ergou/auto_commit_strict: $strict
  ergou/fuzzy: [zh_z, ch_c, sh_s, n_l, en_eng, in_ing]
  ergou/pinyin_correction: true
  ergou/wubi_correction: true
Y
"$bin" "$shared" "$user" "$@" 2>/dev/null
