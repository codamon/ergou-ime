#!/usr/bin/env bash
# ergou-ime — the 2026-11-10 recogniser comparison with our own Swift code.
# SPDX-License-Identifier: GPL-3.0-only
# usage: run-bench.sh [bench dir]   (default ~/Developer/asr-bench: models/, segs/, rec.wav, hot100.txt)
set -uo pipefail
cd "$(dirname "$0")"
B="${1:-$HOME/Developer/asr-bench}"
M="$B/models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"
SV="$B/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
H="二狗输入法,右 Option,五笔,拼音,输入监控,Shift,Claude,GPT,惠灵顿,基督城,奥克兰"
mkdir -p out
./.speech-bench terms || exit 1
run() { local name=$1; shift; echo "== $name"; ./.speech-bench "$@" 2>"out/$name.err" | tee "out/$name.log"; }
run qwen3-cli          asr qwen3 "$M" ""  out/qwen3-cli.txt "$B"/segs/seg*.wav
run qwen3-cli-hot      asr qwen3 "$M" "$H" out/qwen3-cli-hot.txt "$B"/segs/seg*.wav
run qwen3-cli-hot100   asr qwen3 "$M" "@$B/hot100.txt" out/qwen3-cli-hot100.txt "$B"/segs/seg*.wav
run sensevoice-cli     asr sensevoice "$SV" "" out/sensevoice-cli.txt "$B"/segs/seg*.wav
run qwen3-session      session qwen3 "$M" ""  out/qwen3-session.txt "$B/rec.wav"
run qwen3-session-hot  session qwen3 "$M" "$H" out/qwen3-session-hot.txt "$B/rec.wav"
run sensevoice-session session sensevoice "$SV" "" out/sensevoice-session.txt "$B/rec.wav"
