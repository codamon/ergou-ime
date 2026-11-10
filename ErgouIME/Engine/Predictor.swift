// ergou-ime — 联想: next-word suggestions after a commit (D, 2026-11-09).
// SPDX-License-Identifier: GPL-3.0-only
//
// Read-only SQLite (SharedSupport/predict.sqlite, built by
// scripts/fetch-predict.sh from LGPL-3.0 rime-essay/octagram data). Looks up
// the longest suffix (4 → 1 characters) of what was just committed.
// Nothing is learned or written.

import Foundation
import SQLite3

final class Predictor {
    static let shared = Predictor()

    private var db: OpaquePointer?
    private var statement: OpaquePointer?

    private init() {
        guard let url = Bundle.main.sharedSupportURL?.appendingPathComponent("predict.sqlite"),
              sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
        else { db = nil; return }
        sqlite3_prepare_v2(db, "select v from p where k = ? order by w desc limit 6", -1, &statement, nil)
    }

    /// Suggestions for the text just committed; empty when off or unknown.
    func suggestions(after text: String) -> [String] {
        guard SharedSettings.prediction, let statement else { return [] }
        let chars = Array(text.filter { AutoSpace.isHan($0) })
        guard !chars.isEmpty, text.last.map(AutoSpace.isHan) == true else { return [] }
        for n in stride(from: min(4, chars.count), through: 1, by: -1) {
            let key = String(chars.suffix(n))
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            var out: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let c = sqlite3_column_text(statement, 0) { out.append(String(cString: c)) }
            }
            if !out.isEmpty { return out }
        }
        return []
    }
}
