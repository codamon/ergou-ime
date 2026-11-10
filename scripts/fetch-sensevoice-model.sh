#!/usr/bin/env bash
# ergou-ime — download the SenseVoice Small (int8) model for sherpa-onnx.
# SPDX-License-Identifier: GPL-3.0-only
#
# DEVELOPMENT ONLY. End users get the model from ErgouIME Settings, after a
# confirmation dialog (docs/PLAN-v1.md M3). The model is NOT committed and NOT
# bundled into the app.
#
# It goes to the App Group container both sandboxed programs read from
# (Shared/Paths.swift):
#   ~/Library/Group Containers/<TEAMID>.com.codamon.ergou/Models/sense-voice/
# Needs ERGOU_TEAM_ID (or a previous ./scripts/configure.sh run).
# Override with: ERGOU_MODEL_DIR=/some/dir ./scripts/fetch-sensevoice-model.sh
# macOS 15+ may ask Terminal for permission to access another app's data.
#
# Licence: SenseVoice is released by FunAudioLLM/Alibaba under its own model
# licence — read it before redistributing:
#   https://github.com/FunAudioLLM/SenseVoice
#   https://huggingface.co/FunAudioLLM/SenseVoiceSmall
source "$(dirname "$0")/lib/common.sh"
require_macos

MODEL_NAME="sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
MODEL_SHA256="7305f7905bfcf77fa0b39388a313f3da35c68d971661a65475b56fb2162c8e63"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${MODEL_NAME}.tar.bz2"
team="${ERGOU_TEAM_ID:-}"
if [[ -z "$team" && -f "$REPO_ROOT/Config/Local.xcconfig" ]]; then
  team="$(sed -n 's/^ERGOU_TEAM_ID = //p' "$REPO_ROOT/Config/Local.xcconfig")"
fi
if [[ -z "${ERGOU_MODEL_DIR:-}" ]]; then
  [[ -n "$team" ]] || die "set ERGOU_TEAM_ID or ERGOU_MODEL_DIR"
fi
DEST="${ERGOU_MODEL_DIR:-$HOME/Library/Group Containers/$team.com.codamon.ergou/Models/sense-voice}"

archive="$(download_verified "$URL" "$MODEL_SHA256")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
tar -xjf "$archive" -C "$work"

model="$(find "$work" -name 'model.int8.onnx' -print -quit)"
tokens="$(find "$work" -name 'tokens.txt' -print -quit)"
[[ -n "$model" && -n "$tokens" ]] || die "model.int8.onnx / tokens.txt not found in $MODEL_NAME"

mkdir -p "$DEST"
cp "$model" "$tokens" "$DEST/"
printf '%s\n' "$MODEL_NAME" > "$DEST/VERSION"
log "SenseVoice model → $DEST"
