#!/usr/bin/env bash
# ergou-ime — fail if anything but Settings and ErgouIME Cloud could reach the network.
# SPDX-License-Identifier: GPL-3.0-only
#
# Shared/Privacy.swift rules 1, 2 and 11:
#   ErgouIME (input method)   no network. Sources ErgouIME/ + Shared/.
#   ErgouIME Corrector (XPC)  no network. Sources ErgouIMECorrector/ + Shared/.
#   ErgouIME Cloud (XPC)      network.client only (no server), App Group, sandbox.
#   ErgouIME Settings         network.client, for user actions (not scanned).
# CloudShared/ (the API key file) must not be compiled into the input method
# or the Corrector, and ErgouIME/ must not refer to the key.
#
#   ./scripts/check-no-network.sh                 source + entitlements (any OS)
#   ./scripts/check-no-network.sh path/ErgouIME.app   + signed entitlements and
#                                                     imported symbols (macOS)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# 1. Networking APIs in the sources of the programs without network access.
pattern='URLSession|NSURLConnection|URLRequest|NWConnection|NWListener|NWBrowser|import[[:space:]]+Network\b|CFSocket|CFStreamCreatePairWithSocket|getaddrinfo|\bsocket\(|\bconnect\(|WKWebView|import[[:space:]]+WebKit|Data\(contentsOf:[[:space:]]*URL\(string:|Sparkle|SPUUpdater|"https?://'
if hits="$(grep -rnE "$pattern" "$REPO_ROOT/ErgouIME" "$REPO_ROOT/Shared" "$REPO_ROOT/ErgouIMECorrector" "$REPO_ROOT/CloudShared" \
      --include='*.swift' --include='*.m' --include='*.h' --include='*.c' 2>/dev/null \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')"; then
  echo "error: networking API in sources that must stay offline:"; echo "$hits"; fail=1
fi

# 1b. The input method never touches the cloud API key.
if hits="$(grep -rnE 'CloudKeyFile|api-key' "$REPO_ROOT/ErgouIME" --include='*.swift' --include='*.m' --include='*.h' --include='*.c' 2>/dev/null)"; then
  echo "error: input-method sources refer to the cloud API key:"; echo "$hits"; fail=1
fi
# 1c. CloudShared/ only in the ErgouIMECloud and ErgouIMESettings targets.
bad_targets="$(awk '/^  [A-Za-z]+:$/ { t=$1; sub(":", "", t) } /path: CloudShared/ { print t }' "$REPO_ROOT/project.yml" \
  | grep -vxE 'ErgouIMECloud|ErgouIMESettings' || true)"
if [[ -n "$bad_targets" ]]; then
  echo "error: CloudShared/ is compiled into: $bad_targets"; fail=1
fi

# 2. Entitlements files: network only for Settings and Cloud; Cloud client only.
for ent in "$REPO_ROOT/ErgouIME/Supporting/ErgouIME.entitlements" \
           "$REPO_ROOT/ErgouIMECorrector/Supporting/ErgouIMECorrector.entitlements"; do
  if grep -qE '<key>[[:space:]]*com\.apple\.security\.network\.(client|server)' "$ent"; then
    echo "error: $ent grants network access"; fail=1
  fi
done
cloud_ent="$REPO_ROOT/ErgouIMECloud/Supporting/ErgouIMECloud.entitlements"
if grep -qE '<key>[[:space:]]*com\.apple\.security\.network\.server' "$cloud_ent"; then
  echo "error: $cloud_ent grants network.server"; fail=1
fi
cloud_keys="$(grep -oE '<key>[^<]+</key>' "$cloud_ent" | sed -E 's#</?key>##g' | LC_ALL=C sort | tr '\n' ' ')"
if [[ "$cloud_keys" != "com.apple.security.app-sandbox com.apple.security.application-groups com.apple.security.network.client " ]]; then
  echo "error: $cloud_ent must have exactly app-sandbox, application-groups, network.client (has: $cloud_keys)"; fail=1
fi
while IFS= read -r ent; do
  case "$ent" in
    */ErgouIMESettings/*|*/ErgouIMECloud/*) continue ;;
  esac
  if grep -qE '<key>[[:space:]]*com\.apple\.security\.network\.(client|server)' "$ent"; then
    echo "error: $ent grants network access"; fail=1
  fi
done < <(find "$REPO_ROOT" -name '*.entitlements' -not -path '*/vendor/*' -not -path '*/build/*' -not -path '*/.build/*')

# 3. Optional: the built, signed app (macOS only).
app="${1:-}"
if [[ -n "$app" ]]; then
  bin="$app/Contents/MacOS/ErgouIME"
  ents() { codesign -d --entitlements - --xml "$1" 2>/dev/null; }
  if ents "$app" | grep -qE 'network\.(client|server)'; then
    echo "error: signed ErgouIME.app has a network entitlement"; fail=1
  fi
  corrector="$app/Contents/XPCServices/ErgouIMECorrector.xpc"
  if [[ -d "$corrector" ]] && ents "$corrector" | grep -qE 'network\.(client|server)'; then
    echo "error: signed ErgouIMECorrector.xpc has a network entitlement"; fail=1
  fi
  cloud="$app/Contents/XPCServices/ErgouIMECloud.xpc"
  if [[ -d "$cloud" ]]; then
    if ents "$cloud" | grep -q 'network\.server'; then
      echo "error: signed ErgouIMECloud.xpc has network.server"; fail=1
    fi
    if ! ents "$cloud" | grep -q 'network\.client' || ! ents "$cloud" | grep -q 'app-sandbox'; then
      echo "error: signed ErgouIMECloud.xpc is not sandboxed with network.client"; fail=1
    fi
  fi
  # Nothing else nested in the bundle may have network access.
  while IFS= read -r nested; do
    case "$nested" in
      */ErgouIMECloud.xpc|*/ErgouIME\ Settings.app) continue ;;
    esac
    if ents "$nested" | grep -qE 'network\.(client|server)'; then
      echo "error: $(basename "$nested") has a network entitlement"; fail=1
    fi
  done < <(find "$app/Contents" -maxdepth 3 \( -name '*.xpc' -o -name '*.app' \) -type d)
  # Our own binaries must not import socket-level or URL-loading symbols.
  for b in "$bin" "$corrector/Contents/MacOS/ErgouIMECorrector"; do
    [[ -f "$b" ]] || continue
    if nm -u "$b" 2>/dev/null | grep -qE '_socket$|_connect$|_getaddrinfo$|NSURLSession|nw_connection'; then
      echo "error: $(basename "$b") imports networking symbols:"
      nm -u "$b" | grep -E '_socket$|_connect$|_getaddrinfo$|NSURLSession|nw_connection'; fail=1
    fi
  done
  # Vendor dylibs: report only (the sandbox still blocks them at runtime).
  for lib in "$app"/Contents/Frameworks/*.dylib; do
    [[ -f "$lib" ]] || continue
    if nm -u "$lib" 2>/dev/null | grep -qE '_socket$|_connect$|_getaddrinfo$'; then
      echo "note: $(basename "$lib") imports socket symbols (blocked by the sandbox; review)"
    fi
  done
fi

if (( fail )); then exit 1; fi
echo "ok: no network access in the input method or the Corrector; ErgouIME Cloud has network.client only"
