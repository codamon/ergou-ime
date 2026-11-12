// ergou-ime — one candidate, as the engine hands it to the candidate window.
// SPDX-License-Identifier: GPL-3.0-only
//
// In Shared because Settings draws a sample candidate window (设置 › 外观)
// with the input method's own drawing code.

struct Candidate: Equatable {
    var text: String
    var comment: String?
    /// Label shown in front of the candidate, e.g. "1".
    var label: String?
}
