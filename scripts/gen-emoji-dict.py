#!/usr/bin/env python3
# ergou-ime — build the OpenCC tables for emoji and symbol candidates.
# SPDX-License-Identifier: GPL-3.0-only
#
#   python3 scripts/gen-emoji-dict.py EMOJI_TXT COMMIT
#
# EMOJI_TXT is opencc/emoji.txt from rime-ice at COMMIT
# (https://github.com/iDvel/rime-ice, GPL-3.0):
# https://raw.githubusercontent.com/iDvel/rime-ice/<COMMIT>/opencc/emoji.txt
#
# Writes, for simplifier@emoji in our schemas (RimeData/opencc/ergou_emoji.json):
#   RimeData/opencc/ergou_emoji.txt    word → emoji, from rime-ice
#   RimeData/opencc/ergou_symbols.txt  word → symbols, from tools/emoji/symbols.txt
#
# Rules:
#   * only words written in Chinese characters (rime-ice also maps "OK",
#     "Python" …: those would follow the English candidates of 中英混输);
#   * at most 2 emoji per word, 1 for a single character (好, 看, 心 are
#     typed all day; each emoji takes a place in the candidate row);
#   * no emoji newer than Emoji 14.0, the newest that macOS 13.0 (our oldest
#     system) can draw. That is decided with this Python's Unicode tables,
#     so the script insists on Unicode 15.0 (Python 3.12) and removes the
#     Emoji 15.0 additions by hand.
import pathlib
import re
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "RimeData/opencc"
HAN = re.compile(r"^[一-鿿]+$")
EMOJI_15 = {0x1FAE8, 0x1FA75, 0x1FA76, 0x1FA77, 0x1FAF7, 0x1FAF8, 0x1FACE, 0x1FACF, 0x1FADA, 0x1FADB,
            0x1FAAD, 0x1FAAE, 0x1FAAF, 0x1FA87, 0x1FA88, 0x1FABB, 0x1FABC, 0x1FABD, 0x1FABF, 0x1F6DC}


def drawable(emoji):
    for ch in emoji:
        cp = ord(ch)
        if cp in EMOJI_15 or (cp > 0x7F and unicodedata.category(ch) == "Cn"):
            return False
    return True


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: gen-emoji-dict.py EMOJI_TXT COMMIT")
    if unicodedata.unidata_version != "15.0.0":
        sys.exit(f"needs Python with Unicode 15.0.0 (3.12); this one has {unicodedata.unidata_version}")
    src, commit = pathlib.Path(sys.argv[1]), sys.argv[2]

    emoji = {}
    for line in src.read_text(encoding="utf-8").splitlines():
        if "\t" not in line:
            continue
        word, forms = line.split("\t", 1)
        if not HAN.match(word):
            continue
        keep = [f for f in forms.split(" ")[1:] if f and drawable(f)][: 1 if len(word) == 1 else 2]
        if keep and word not in emoji:
            emoji[word] = keep

    symbols = {}
    for n, line in enumerate((ROOT / "tools/emoji/symbols.txt").read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        word, _, forms = line.partition("\t")
        forms = forms.split(" ")
        if not HAN.match(word) or not forms or len(forms) > 4 or any(not f or "\t" in f for f in forms):
            sys.exit(f"symbols.txt:{n}: want 词<TAB>符号 符号 (at most 4)")
        if word in symbols:
            sys.exit(f"symbols.txt:{n}: duplicate {word}")
        symbols[word] = forms
        # One table per word: OpenCC takes the first table that has it.
        emoji.pop(word, None)

    def write(name, table, source):
        body = "".join(f"{w}\t{w} {' '.join(forms)}\n" for w, forms in sorted(table.items()))
        (OUT / name).write_text(body, encoding="utf-8")
        print(f"{name}: {len(table)} words ({source})")

    OUT.mkdir(parents=True, exist_ok=True)
    write("ergou_emoji.txt", emoji, f"rime-ice {commit[:7]}")
    write("ergou_symbols.txt", symbols, "tools/emoji/symbols.txt")


if __name__ == "__main__":
    main()
