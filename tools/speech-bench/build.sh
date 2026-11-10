#!/usr/bin/env bash
# ergou-ime — build speech-bench from the input method's own Swift files (Mac only).
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")"
V=../../vendor/sherpa-onnx           # scripts/fetch-sherpa-onnx.sh
S=../../ErgouIME/Speech
swiftc -O -D ERGOU_WITH_SHERPA -o .speech-bench \
  main.swift term-tests.swift \
  $S/SpeechTranscriber.swift $S/SenseVoiceTranscriber.swift $S/Qwen3Transcriber.swift $S/FinalPass.swift \
  $S/TermStore.swift $S/SpeechSegmenter.swift ../../ErgouIME/Support/SecureInput.swift ../../Shared/*.swift \
  -import-objc-header bridge.h -I$V/include -L$V/lib -lsherpa-onnx-c-api \
  -Xlinker -rpath -Xlinker "$PWD/$V/lib"
echo "built $(pwd)/.speech-bench"
