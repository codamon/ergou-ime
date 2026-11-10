# ergou-ime — helpers shared by scripts/*.sh. Source, don't run.
# SPDX-License-Identifier: GPL-3.0-only
#
# These scripts run on the developer's Mac, by hand. The input method itself
# never downloads anything (see ErgouIME/Support/Privacy.swift).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor"
CACHE_DIR="${ERGOU_CACHE_DIR:-$VENDOR_DIR/.downloads}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this script must run on macOS"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1${2:+ ($2)}"
}

sha256_of() {
  shasum -a 256 "$1" | awk '{print $1}'
}

# download_verified URL SHA256 → prints the cached file path.
# Re-uses the cached file when its checksum matches; refuses mismatches.
download_verified() {
  local url="$1" expected="$2"
  local file="$CACHE_DIR/$(basename "$url")"
  mkdir -p "$CACHE_DIR"
  if [[ -f "$file" && "$(sha256_of "$file")" == "$expected" ]]; then
    printf '%s\n' "$file"; return
  fi
  log "Downloading $(basename "$url")" >&2
  curl -fL --retry 3 --progress-bar -o "$file.part" "$url"
  local actual; actual="$(sha256_of "$file.part")"
  if [[ "$actual" != "$expected" ]]; then
    rm -f "$file.part"
    die "checksum mismatch for $(basename "$url"): expected $expected, got $actual"
  fi
  mv "$file.part" "$file"
  printf '%s\n' "$file"
}

# Signing on the maintainer's Mac. The Developer identities live in their own
# keychain because the login keychain is locked in SSH sessions. Paths and the
# notarytool profile name can be overridden in ~/.config/ergou-ime/signing.env
# (never in the repository), e.g.
#   ERGOU_SIGNING_KEYCHAIN="$HOME/Library/Keychains/my-signing.keychain-db"
#   ERGOU_SIGNING_PASS_FILE="$HOME/.config/my/keychain-pass"
#   ERGOU_NOTARY_PROFILE=my-notary
load_signing_env() {
  local env_file="${ERGOU_SIGNING_ENV:-$HOME/.config/ergou-ime/signing.env}"
  # shellcheck disable=SC1090
  [[ -f "$env_file" ]] && source "$env_file"
  ERGOU_SIGNING_KEYCHAIN="${ERGOU_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/ergou-signing.keychain-db}"
  ERGOU_SIGNING_PASS_FILE="${ERGOU_SIGNING_PASS_FILE:-$HOME/.config/ergou-ime/signing-keychain-pass}"
  ERGOU_NOTARY_PROFILE="${ERGOU_NOTARY_PROFILE:-ergou-notary}"
  [[ -f "$ERGOU_SIGNING_KEYCHAIN" && -f "$ERGOU_SIGNING_PASS_FILE" ]] \
    || die "signing keychain not set up: $ERGOU_SIGNING_KEYCHAIN (see scripts/lib/common.sh)"
}

unlock_signing_keychain() {
  security unlock-keychain -p "$(cat "$ERGOU_SIGNING_PASS_FILE")" "$ERGOU_SIGNING_KEYCHAIN"
}

# team_id → the Team ID from Config/Local.xcconfig (written by configure.sh).
team_id() {
  local team
  team="$(sed -n 's/^ERGOU_TEAM_ID = //p' "$REPO_ROOT/Config/Local.xcconfig" 2>/dev/null)"
  [[ -n "$team" ]] || die "no ERGOU_TEAM_ID in Config/Local.xcconfig — run scripts/configure.sh"
  printf '%s\n' "$team"
}

lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
