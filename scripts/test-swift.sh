#!/usr/bin/env bash
# ergou-ime — build and run the Swift unit tests (tests/swift, no XCTest).
# SPDX-License-Identifier: GPL-3.0-only
#
# macOS only. Compiles tests/swift/*.swift together with Shared/*.swift and
# the input-method files listed in ERGOU_IME_SOURCES into one command-line
# binary under build/test-swift, runs it, and exits with its status.
#
#   ./scripts/test-swift.sh
source "$(dirname "$0")/lib/common.sh"

require_macos
require_cmd swiftc "install Xcode or the command line tools"

# Files from ErgouIME/ that the tests need. They must compile without the
# rest of the input method (no InputMethodKit, no bridging header).
ERGOU_IME_SOURCES=(
  ErgouIME/Speech/CorrectionStore.swift
  ErgouIME/Speech/CorrectionTracker.swift
  ErgouIME/Speech/CorrectionRouting.swift
  ErgouIME/Speech/TermStore.swift
  ErgouIME/Engine/AutoSpace.swift
  ErgouIME/Support/SecureInput.swift
)

out_dir="$REPO_ROOT/build/test-swift"
mkdir -p "$out_dir"

sources=("$REPO_ROOT"/tests/swift/*.swift "$REPO_ROOT"/Shared/*.swift)
for f in ${ERGOU_IME_SOURCES[@]+"${ERGOU_IME_SOURCES[@]}"}; do sources+=("$REPO_ROOT/$f"); done

log "compiling ${#sources[@]} files"
swiftc -swift-version 5 -Onone -o "$out_dir/ergou-tests" -module-cache-path "$out_dir/module-cache" "${sources[@]}"
log "running"
exec "$out_dir/ergou-tests"
