#!/usr/bin/env bash
# ergou-ime — build the 联想 (next-word prediction) database.
# SPDX-License-Identifier: GPL-3.0-only
#
# Source: rime/librime-predict release data-1.0 predict.txt (from rime-essay
# and rime-octagram-data, both LGPL-3.0). It is Traditional Chinese; we
# convert it with OpenCC t2s (from librime's rime-deps bundle, Apache-2.0),
# keep at most 6 continuations per key (at most 2 single characters, so
# 的/是 do not crowd out words), drop rare keys, and write SQLite:
#   vendor/predict/predict.sqlite   table p(k, v, w), index on k
# The input method only reads it (ErgouIME/Engine/Predictor.swift).
source "$(dirname "$0")/lib/common.sh"
require_macos
require_cmd python3

PREDICT_URL="https://github.com/rime/librime-predict/releases/download/data-1.0/predict.txt"
PREDICT_SHA="df0f7a9ef96569da402d9ea2376aefad4d15382ebcccb05ec84a0acbc00c7f83"
DEPS_URL="https://github.com/rime/librime/releases/download/1.17.0/rime-deps-33e7814-macOS-universal.tar.bz2"
DEPS_SHA="dfe6047e87be271963d7466bd1a6e3d9e660c30e5e73e4bb94e8782c0a6ac8df"

txt="$(download_verified "$PREDICT_URL" "$PREDICT_SHA")"
deps="$(download_verified "$DEPS_URL" "$DEPS_SHA")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tar -xjf "$deps" -C "$work" bin/opencc share/opencc lib
DYLD_LIBRARY_PATH="$work/lib" "$work/bin/opencc" -c "$work/share/opencc/t2s.json" -i "$txt" -o "$work/predict.s.txt"

dest="$VENDOR_DIR/predict"
mkdir -p "$dest"
python3 - "$work/predict.s.txt" "$dest/predict.sqlite" <<'PY'
import collections, os, sqlite3, sys
src, out = sys.argv[1], sys.argv[2]
rows = collections.defaultdict(list)
for line in open(src, encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) != 3 or p[0] == "$":
        continue
    try:
        rows[p[0]].append((int(p[2]), p[1]))
    except ValueError:
        pass
if os.path.exists(out):
    os.remove(out)
db = sqlite3.connect(out)
db.execute("create table p(k text not null, v text not null, w integer not null)")
n = 0
for k, lst in rows.items():
    lst.sort(reverse=True)
    if lst[0][0] < 500:
        continue
    seen, singles, top = set(), 0, []
    for w, v in lst:
        if v in seen:
            continue
        if len(v) == 1:
            if singles >= 2:
                continue
            singles += 1
        seen.add(v)
        top.append((k, v, w))
        if len(top) >= 6:
            break
    db.executemany("insert into p values (?,?,?)", top)
    n += len(top)
db.execute("create index pk on p(k)")
db.commit()
db.execute("vacuum")
db.close()
print(f"{n} predictions, {os.path.getsize(out) // 1024} KB")
PY
log "prediction db → $dest"
