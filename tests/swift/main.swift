// ergou-ime — tiny test runner for the Swift unit tests (no XCTest).
// SPDX-License-Identifier: GPL-3.0-only
//
// Built and run by scripts/test-swift.sh on a Mac. Each test file defines
// a list of named test functions (`let xxxTests: [Test]`); add that list to
// `suites` below. A test reports through check / expect; the runner prints
// every failure and exits 1, or prints "all N tests passed" and exits 0.

import Foundation

typealias Test = (name: String, run: () -> Void)

let suites: [[Test]] = [
    editCorrectionTests,
    correctionStoreTests,
    correctionTrackerTests,
    correctionWiringTests,
    tidyGuardTests,
    inputSourceSwitchTests,
]

var currentTest = ""
var failures: [String] = []

func check(_ cond: Bool, _ name: String) {
    if !cond { failures.append("\(currentTest): \(name)") }
}

/// check(got == want) that also prints both values on failure.
func expect<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    if got != want { failures.append("\(currentTest): \(name)\n    got:  \(got)\n    want: \(want)") }
}

var count = 0
for test in suites.joined() {
    currentTest = test.name
    test.run()
    count += 1
}

if failures.isEmpty {
    print("all \(count) tests passed")
    exit(0)
}
for f in failures { print("FAIL \(f)") }
print("\(failures.count) failure(s) in \(count) tests")
exit(1)
