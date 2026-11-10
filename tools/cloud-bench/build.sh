#!/usr/bin/env bash
# ergou-ime — build cloud-bench from the cloud tidy-up's own Swift files (Mac only).
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")"
R=../..
swiftc -O -o .cloud-bench main.swift tests.swift \
  $R/ErgouIMECloud/CloudClient.swift $R/CloudShared/CloudKeyFile.swift \
  $R/ErgouIME/Speech/TermStore.swift $R/ErgouIME/Speech/CorrectorClient.swift $R/ErgouIME/Speech/CloudStream.swift $R/ErgouIME/Support/SecureInput.swift \
  $R/Shared/*.swift
echo "built $(pwd)/.cloud-bench"
