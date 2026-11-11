#!/bin/bash
# ergou-ime — 卸载二狗输入法，并删除设置、词库、语音记录和模型（会先列出再询问）。双击运行。
# SPDX-License-Identifier: GPL-3.0-only
here="$(cd "$(dirname "$0")" && pwd)"
copy="$(mktemp -t ergou-uninstall)" && cp "$here/uninstall.sh" "$copy" && exec /bin/bash "$copy" --all
