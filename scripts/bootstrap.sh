#!/usr/bin/env bash
# ergou-ime — one-shot setup on a Mac.
# SPDX-License-Identifier: GPL-3.0-only
#
# Needs: export ERGOU_TEAM_ID=<your Apple Developer Team ID> (first run).
#
#   ./scripts/bootstrap.sh              passthrough build only (no downloads)
#   ./scripts/bootstrap.sh --rime       + librime and Wubi data
#   ./scripts/bootstrap.sh --speech     + sherpa-onnx and SenseVoice model (dev only;
#                                       users download it in ErgouIME Settings)
#   ./scripts/bootstrap.sh --all        everything
source "$(dirname "$0")/lib/common.sh"
require_macos
require_cmd xcodegen "brew install xcodegen"

want_rime=0 want_speech=0
for arg in "$@"; do
  case "$arg" in
    --rime) want_rime=1 ;;
    --speech) want_speech=1 ;;
    --all) want_rime=1; want_speech=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done

scripts="$REPO_ROOT/scripts"
if (( want_rime )); then
  "$scripts/fetch-librime.sh"
  "$scripts/fetch-rime-data.sh"
fi
if (( want_speech )); then
  "$scripts/fetch-sherpa-onnx.sh"
  "$scripts/fetch-sensevoice-model.sh"
fi

"$scripts/configure.sh"
(cd "$REPO_ROOT" && xcodegen generate)
log "Done. Open ErgouIME.xcodeproj, or run ./scripts/install.sh"
