#!/usr/bin/env python3
# ergou-ime — build the menu-bar icon PDF from docs/icon/menu-icon.svg.
# SPDX-License-Identifier: GPL-3.0-only
#
#   python3 scripts/make-menu-icon.py   → ErgouIME/Resources/ergou.pdf
#
# One SVG unit = one PDF point. The menu bar draws input-source icons at most
# about 16 pt high, so the icon is a 22×16 pt page (Squirrel's rime.pdf is
# 22×16 pt too) with the dog itself as the shape — solid head, eyes and muzzle
# cut out, no background badge — as large as fits, like the WeChat icon next
# to it. History (user reports, 2026-11-11): the first ergou.pdf was 12×12 pt
# (a converter read 16 px as 12 pt); a 16×16 pt badge with the dog cut out
# still looked smaller than its neighbours.
#
# The SVG must be a single <path> made of M/L/Z commands (absolute
# coordinates), filled black with the even-odd rule — what
# docs/icon/menu-icon.svg is. Anything else is refused rather than drawn wrong.
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
svg = (root / "docs/icon/menu-icon.svg").read_text()
out = root / "ErgouIME/Resources/ergou.pdf"

view = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
paths = re.findall(r'<path\b[^>]*\bd="([^"]+)"', svg)
if not view or len(paths) != 1 or 'fill-rule="evenodd"' not in svg:
    sys.exit("expected one even-odd <path> and a viewBox in menu-icon.svg")
width, height = float(view.group(1)), float(view.group(2))

ops = []
for cmd, args in re.findall(r"([MLZ])([^MLZ]*)", paths[0]):
    nums = [float(n) for n in re.findall(r"-?[\d.]+", args)]
    if cmd == "Z":
        ops.append("h")
        continue
    if len(nums) != 2:
        sys.exit(f"unexpected {cmd} arguments: {args!r}")
    x, y = nums
    ops.append(f"{x:.3f} {height - y:.3f} {'m' if cmd == 'M' else 'l'}")   # flip y
leftover = re.sub(r"[MLZ\d.,\s-]", "", paths[0])
if leftover:
    sys.exit(f"unsupported path commands: {sorted(set(leftover))}")

content = ("0 0 0 rg\n" + "\n".join(ops) + "\nf*\n").encode()
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width:g} {height:g}] /Contents 4 0 R /Resources << >> >>".encode(),
    b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream",
]
pdf = bytearray(b"%PDF-1.4\n")
offsets = []
for i, body in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf += b"%d 0 obj\n" % i + body + b"\nendobj\n"
xref = len(pdf)
pdf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
pdf += b"".join(b"%010d 00000 n \n" % o for o in offsets)
pdf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
out.write_bytes(pdf)
print(f"{out.relative_to(root)}: {width:g}×{height:g} pt, {len(ops)} path ops, {len(pdf)} bytes")
