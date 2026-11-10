// ergou-ime — Objective-C/C bridging header.
// SPDX-License-Identifier: GPL-3.0-only
//
// C headers of optional native dependencies. They are only visible when
// scripts/configure.sh has put their include directories on
// HEADER_SEARCH_PATHS (see Config/ErgouIME.xcconfig); otherwise these blocks
// are skipped and the Swift code that uses them is compiled out via
// ERGOU_WITH_RIME / ERGOU_WITH_SHERPA.

#if __has_include(<rime_api.h>)
#include <rime_api.h>
#endif

#if __has_include(<sherpa-onnx/c-api/c-api.h>)
#include <sherpa-onnx/c-api/c-api.h>
#endif
