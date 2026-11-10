#!/bin/bash
# ergou-ime — move the input method to /Library/Input Methods (all users).
# SPDX-License-Identifier: GPL-3.0-only
# Run once in Terminal with:  sudo bash ./scripts/install-system.sh
# The bundle is then owned by you, so later builds can be copied into it
# without sudo (scripts/install.sh --system).
set -euo pipefail
user="${SUDO_USER:?run with sudo}"
home="$(eval echo ~"$user")"
src="${1:-$(cd "$(dirname "$0")/.." && pwd)/build/signed/Build/Products/Release/ErgouIME.app}"
dest="/Library/Input Methods/ErgouIME.app"
[[ -d "$src" ]] || { echo "build not found: $src"; exit 1; }
pkill -x ErgouIME 2>/dev/null || true
rm -rf "$dest"
cp -R "$src" "$dest"
chown -R "$user":staff "$dest"
rm -rf "$home/Library/Input Methods/ErgouIME.app"
sudo -u "$user" "$dest/Contents/MacOS/ErgouIME" --register-input-source || true
echo "Installed to $dest (owned by $user); removed the copy in ~/Library/Input Methods."
