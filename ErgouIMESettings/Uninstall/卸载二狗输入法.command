#!/bin/bash
# ergou-ime — 卸载二狗输入法（保留设置、词库和模型）。双击运行。
# SPDX-License-Identifier: GPL-3.0-only
# The script lives inside the app it removes: run a copy.
here="$(cd "$(dirname "$0")" && pwd)"
copy="$(mktemp -t ergou-uninstall)" && cp "$here/uninstall.sh" "$copy" && exec /bin/bash "$copy"
