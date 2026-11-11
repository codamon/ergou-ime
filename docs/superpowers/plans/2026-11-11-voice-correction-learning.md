# Voice Correction Learning (0.5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a voice result is typed, notice when the user replaces a word in the same text field, learn "heard A → meant B" on this Mac, and from then on silently fix A to B in later voice results.

**Architecture:**
- **Pure logic in `Shared/EditCorrection.swift`**: diff, word boundaries, guards, replacement, and the revert/veto decision. It is tested with a swiftc test binary on the Mac.
- **Tracking state machine in `ErgouIME/Speech/CorrectionTracker.swift`**: reads the field through a small protocol, so it can be tested with a fake.
- **Rule store in `ErgouIME/Speech/CorrectionStore.swift`**: the input method's private container only.
- **Glue in the controller and `VoiceSession.deliver`.**
- Learned terms keep flowing into the existing 我的词 / hotword machinery via `TermStore.record(…, source: .edit)`.

**Tech Stack:** Swift 6 / InputMethodKit / SwiftUI (Settings). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-11-voice-correction-learning-design.md`

## Global Constraints

- **Privacy**:
  - Nothing leaves the Mac. Only the input method process (no network) reads text fields or writes rules.
  - Context text read from the field is kept in memory only, and dropped when tracking ends.
  - Never read or record while `SecureInput.isActive`.
- **Rule storage**: rules live in `Paths.privateRoot/voice-corrections.json`. They are never read from the App Group container, which Settings can write.
- **Validation**: both sides of a pair must pass `VoiceTermRules.term`, and they must still differ after ignoring case.
- **Switch**: `SettingKey.learnFromEdits`, default `true`. When off: no tracking AND no replacement. Existing hotwords stay.
- **Learn-diff limits**: at most 2 changed spans; total changed characters ≤ half of the original; neither side of a span empty.
  - A trailing pure insertion (the user kept typing) is ignored.
- **Latin heard (A)**:
  - Rule: A must be ≥ 3 characters and not in `CommonWords`. Otherwise only the term B is recorded (hotword, no rule).
  - Replacement: whole-word match, case-insensitive; output is B's spelling.
- **Han heard (A)**:
  - Rule: A must be ≥ 2 Han characters and not in `CommonWords`.
  - Single-character change: pad within the same Han run, 1 character left and 1 right, to 3 characters; if one side runs out, pad more on the other.
  - Multi-character change: the changed span itself, at most 6 characters.
  - Matching is by substring.
- **Mixed-script change**: the span is used as-is, without padding.
- **Case-only edits and punctuation-only edits**: never learned.
- **Revert**:
  - Replaced B changed back to A → delete A → B and veto it.
  - Replaced B changed to C → veto A → B and learn A → C.
- **Tracking**:
  - Starts on `insertVoiceText` only, not via `ForeignInsert`.
  - Lasts at most 60 s; one insertion at a time.
  - Ends (with a final compare) on: Return / Tab / Esc keyDown (compare before the key reaches the app), `deactivateServer`, a new voice insertion, or timeout.
  - Field reads are at most 1 per second, and never while marked text is up.
- **Rule store limit**: 300 rules; when full, drop the least recently used.
- **Two sightings before replacing** (user decision 2026-11-11: wrong "fixes" annoy more than missed ones): `CorrectionStore.learn` counts sightings per pair (heard case-insensitive + term case-insensitive). `rules` returns only pairs seen ≥ 2 times. The first sighting still records the term as a hotword via TermStore. A different term for the same heard resets the count to 1 for the new pair.
- **Releases**: this is 0.5.0 (feature → minor). The release itself is not part of this plan; it happens after the user has tested the build.

## Review Focus

1. **Return sends the message and empties the field** (chat apps). The compare must run before Return reaches the app. Pinned in Task 5 (`finishOnReturnComparesFirst`).
2. **The user deletes the whole insertion and dictates again.** Nothing is learned. Pinned in Task 2 (`wholeRewriteLearnsNothing`) and Task 5 (`anchorLostLearnsNothing`).
3. **A real word that equals a learned A** (e.g. "Orca" used on purpose). It is still replaced, but changing it back vetoes the rule. Pinned in Task 2 (`revertVetoes`).
4. **Han text containing A as part of a longer word** (生肖 inside 生肖日 vs the rule 生肖日→生效日). Only the exact 3-character A matches. Pinned in Task 2 (`hanSingleCharPadsToThree`) and Task 3 (`hanSubstringOnlyExactRule`).
5. **Apps without text access** (`attributedSubstring` returns nil, e.g. terminals). Tracking silently does nothing. Pinned in Task 5 (`unreadableClientNoTracking`).

---

### Task 1: Dev builds signed with Developer ID (no more microphone re-prompt)

**Files:**
- Modify: `scripts/build-signed.sh` (the `xcodebuild` call, around line 26)

**Interfaces:** none.

- [ ] **Step 1:** In `build-signed.sh`, after `kc=…`, look up `security find-identity -v -p codesigning "$kc"`. Pick `Developer ID Application: … ($team)` when present, else fall back to `Apple Development`. Pass the chosen identity as `CODE_SIGN_IDENTITY`. Log which one was used. Update the header comment: same identity as releases, so TCC grants (microphone, input monitoring) survive switching between dev and release builds.
- [ ] **Step 2:** On the Mac: `rsync` (flags in memory `ergou-mac-testing`), then `ssh mac 'bash -lc "cd ~/Developer/ergou-ime-build/src && xcodegen generate -q && ./scripts/build-signed.sh --no-install"'`. Then `codesign -d -r- build/signed/Build/Products/Release/ErgouIME.app`.
  Expected: the designated requirement contains `certificate leaf[subject.OU] = ZKTR7N4MK5` and `6.2.6`, i.e. the same as the installed 0.4.2.
- [ ] **Step 3:** Commit: `build-signed.sh：开发版也用 Developer ID 签名，切换开发版和正式版不再要麦克风权限`.

### Task 2: Pure correction logic — diff, boundaries, guards, outcome

**Files:**
- Create: `Shared/EditCorrection.swift`
- Create: `Shared/CommonWords.swift`
- Create: `tests/swift/main.swift` (tiny runner: `check(_ cond: Bool, _ name: String)`, a list of test functions, exit 1 on failure)
- Create: `tests/swift/EditCorrectionTests.swift`
- Create: `scripts/test-swift.sh` (macOS only; compiles `tests/swift/*.swift Shared/*.swift ErgouIME/Speech/CorrectionTracker.swift` once that exists, runs the binary)

**Interfaces — Produces:**
```swift
struct CorrectionPair: Codable, Equatable, Hashable { var heard: String; var term: String }
enum CorrectionEvent: Equatable {
    case learn(CorrectionPair)      // build a replacement rule (and record the term)
    case hotword(String)            // record the term only (guard failed for A)
    case veto(CorrectionPair)       // the user undid our replacement
}
enum CommonWords { static func contains(_ s: String) -> Bool }   // case-insensitive
enum EditCorrection {
    /// original = what was typed; current = the same region now (may have extra trailing text);
    /// applied = rules used when typing it.
    static func outcome(original: String, current: String, applied: [CorrectionPair]) -> [CorrectionEvent]
}
```

- [ ] **Step 1: Write failing tests** in `EditCorrectionTests.swift`:
  - `latinWordLearned`: outcome("用 Orca 看一下", "用 rea 看一下", []) == [.learn(.init(heard: "Orca", term: "rea"))]
  - `latinWordExpandsToWholeWord`: ("这个 SBP API 怎么计费的呢", "这个 sub2api 怎么计费的呢") → [.learn(heard: "SBP API", term: "sub2api")]. The space-separated tokens merge into one span.
  - `hanSingleCharPadsToThree`: ("生肖日按审批", "生效日按审批") → [.learn(heard: "生肖日", term: "生效日")]
  - `hanAtRunEdgePadsOtherSide`: ("肖日审批", "效日审批") → [.learn(heard: "肖日审", term: "效日审")]
  - `hanMultiCharUsesSpan`: ("B 中也是 USD", "币种也是 USD") → [.learn(heard: "B 中", term: "币种")]
  - `commonWordsLearnNothing`: ("this is a test", "this is the test") → []  (A fails the guard and B is common too)
  - `shortLatinOnlyHotword`: ("用 RA 看", "用 REA 看") → [.hotword("REA")]  (A has 2 characters)
  - `caseOnlyIgnored`: ("用 orca", "用 Orca") → []
  - `punctuationOnlyIgnored`: ("要重新给。麦克风", "要重新给麦克风") → []
  - `pureDeletionIgnored`: ("快速的狐狸", "狐狸") → []
  - `wholeRewriteLearnsNothing`: ("今天天气不错", "明天开会") → []
  - `threeSpansLearnsNothing`: three separate word changes → []
  - `trailingTypingIgnored`: ("用 Orca 看", "用 rea 看一下吧") → [.learn(heard: "Orca", term: "rea")]
  - `twoSpansEachJudged`: ("Orca 和 SBP API", "rea 和 sub2api") → two .learn events, in text order
  - `revertVetoes`: outcome("用 rea 看", "用 Orca 看", applied: [.init(heard: "Orca", term: "rea")]) == [.veto(.init(heard: "Orca", term: "rea"))]
  - `changeToThirdWord`: same applied, current "用 REA 看" → [.veto(Orca→rea), .learn(Orca→REA)]
  - `invalidTermDropped`: a term that `VoiceTermRules.term` rejects (contains "@") → []
- [ ] **Step 2:** `scripts/test-swift.sh` on the Mac. Expected: compile error / FAIL (types missing).
- [ ] **Step 3: Implement.**
  - Diff: character-level LCS / Myers over `Array(original)` vs `Array(current)`. Trim a trailing pure insertion.
  - Order matters, because a character diff fragments words (Orca→rea is "O" deleted + "c"→"e"):
    1. group the edits into raw spans;
    2. expand every Latin span to word boundaries (letters, digits, `-_.+#`) on both sides;
    3. merge spans that overlap or are separated only by spaces;
    4. only then apply the limits from Global Constraints (span count, changed ≤ half, measured as max(old, new) characters per span; no empty side);
    5. apply the Han padding rule to single-Han-character spans, using the same padded context on both sides.
  - Then validate with `VoiceTermRules.term` and drop case-only and punctuation-only spans.
  - Classify:
    - A is a revert of an applied rule (old side == applied.term, case-insensitive): veto, plus learn A → new if the new side differs from applied.heard;
    - A fails the guard: hotword(B) when B itself is ≥ 3 characters (Latin) or ≥ 2 Han and not in `CommonWords`, else nothing;
    - otherwise: learn.
  - `CommonWords`: a few hundred English words (articles, pronouns, auxiliaries, prepositions, conjunctions, common verbs and nouns) plus Chinese function and common words (的 了 是 在 和 这个 那个 我们 你们 他们 一个 什么 怎么 可以 没有 就是 但是 因为 所以 然后 现在 已经 还是 如果 这样 那样 …).
- [ ] **Step 4:** `scripts/test-swift.sh`. Expected: `all N tests passed`.
- [ ] **Step 5:** Commit: `VoiceCorrection：从用户的修改里提取词对（纯函数 + 测试）`.

### Task 3: Replacement

**Files:**
- Modify: `Shared/EditCorrection.swift`
- Modify: `tests/swift/EditCorrectionTests.swift`

**Interfaces — Produces:**
```swift
extension EditCorrection {
    /// Rules applied left to right, longest heard first, no overlapping matches.
    static func apply(_ text: String, rules: [CorrectionPair]) -> (text: String, applied: [CorrectionPair])
}
```

- [ ] **Step 1: Failing tests:**
  - `replaceLatinWholeWord`: apply("问 orca 吧", [Orca→rea]) == ("问 rea 吧", [Orca→rea])
  - `latinNotInsideWord`: apply("Orcanet", [Orca→rea]).text == "Orcanet"
  - `hanSubstringOnlyExactRule`: apply("生肖属相", [生肖日→生效日]).text == "生肖属相"; apply("生肖日起", same).text == "生效日起"
  - `longestFirst`: rules [SBP→x, SBP API→sub2api], apply("SBP API 好") → "sub2api 好"
  - `appliedListedOncePerRule` even when a rule matches twice.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. For Latin matching, a match must not touch a letter or digit on either side.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit: `EditCorrection.apply：按学到的规则替换`.

### Task 4: CorrectionStore (private rules) and TermSource.edit

**Files:**
- Create: `ErgouIME/Speech/CorrectionStore.swift`
- Modify: `Shared/VoiceTerms.swift` (add `case edit` to `TermSource` with doc comment "用户在输入框里改出来的")
- Modify: `ErgouIME/Speech/TermStore.swift` (callback `var onTermDeleted: ((String) -> Void)?`, called for each `.delete` edit applied in `applyPendingEdits`)
- Modify: `ErgouIMESettings/Views/TermsView.swift` (`LearnedTermRow.detail`: prepend "你改过" when `term.source == .edit`)
- Test: `tests/swift/CorrectionStoreTests.swift`; add `ErgouIME/Speech/CorrectionStore.swift` to `scripts/test-swift.sh`

**Interfaces — Produces:**
```swift
final class CorrectionStore {            // main thread only
    static let shared = CorrectionStore(file: Paths.privateRoot.appendingPathComponent("voice-corrections.json"))
    init(file: URL)
    var rules: [CorrectionPair] { get }  // most recently used first
    func learn(_ pair: CorrectionPair)   // ignored if vetoed; refreshes lastUsed
    func veto(_ pair: CorrectionPair)    // removes rule, remembers veto (max 300)
    func used(_ pairs: [CorrectionPair]) // bump lastUsed after a replacement
    func removeRules(forTerm term: String)
}
```
The file holds `{version: 1, rules: [{heard, term, learned, lastUsed}], vetoed: [{heard, term}]}`. Reads go through `SafeFile.read(maxBytes: 1 << 20)`. Every entry is re-validated with `VoiceTermRules.term`. Writes are `.atomic`. Keys compare case-insensitively on `heard`; a new rule with the same heard replaces the old one.

- [ ] **Step 1: Failing tests** (temp directory file):
  - `learnPersists`: learn, new instance, rules contains the pair
  - `vetoBlocksRelearn`: veto, then learn the same pair → not in rules
  - `sameHeardReplaces`: learn Orca→rea, learn Orca→REA → rules == [Orca→REA]
  - `capDropsLeastRecentlyUsed`: 301 learns → count 300, the first one is gone
  - `removeRulesForTerm`
  - `corruptFileIgnored`: write garbage → rules empty, no crash
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement the store. Wire `TermStore.shared.onTermDeleted = { CorrectionStore.shared.removeRules(forTerm: $0) }` where `TermStore.shared.start()` is called (`InputEngine` start-up). Add the TermsView label.
- [ ] **Step 4:** Run. Expected: PASS. Build the Settings and IME targets: `xcodebuild … -quiet build`, no errors.
- [ ] **Step 5:** Commit: `CorrectionStore：替换规则存在输入法私有目录；我的词显示“你改过”`.

### Task 5: CorrectionTracker

**Files:**
- Create: `ErgouIME/Speech/CorrectionTracker.swift` (Foundation + Shared only; no InputMethodKit)
- Test: `tests/swift/CorrectionTrackerTests.swift` (fake field)

**Interfaces — Produces:**
```swift
protocol CorrectionField: AnyObject {
    var length: Int { get }                      // UTF-16 units, NSNotFound/0 if unknown
    func text(in range: NSRange) -> String?      // nil = app does not tell us
    var hasMarkedText: Bool { get }
    var identity: ObjectIdentifier { get }       // the underlying client; adapters are created per call
}
final class CorrectionTracker {                  // main thread only
    enum EndReason { case completionKey, focusLost, newInsertion, timeout }
    init(onEvents: @escaping ([CorrectionEvent]) -> Void,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         isEnabled: @escaping () -> Bool = { SharedSettings.learnFromEdits },
         isSecure: @escaping () -> Bool = { false })
    static let maxDuration: TimeInterval = 60
    static let minReadInterval: TimeInterval = 1
    /// Call right after insertText. `start` = UTF-16 location where `inserted` begins.
    func begin(field: CorrectionField, start: Int, inserted: String, applied: [CorrectionPair])
    /// After a key was handled: compare at most once per minReadInterval; ends on timeout.
    func keyHandled(field: CorrectionField)
    /// Final compare (if still tracking this field), then stop.
    func finish(field: CorrectionField?, reason: EndReason)
}
```
- At `begin`: capture up to 16 UTF-16 units before `start` (`anchorBefore`) and up to 16 after the insertion (`anchorAfter`) from the field. If the field gives nil for the inserted range itself, do not track.
- Locating the region:
  - read `[start-anchorLen, start + inserted.utf16.count + 64 + anchorAfterLen]`, clipped to `length`;
  - the region starts after `anchorBefore` (must still match exactly at the same offset, else stop: nothing learned);
  - it ends before the first occurrence of `anchorAfter` (or at window end when `anchorAfter` is empty).
- `finish(field:)` with a different `identity` than the tracked one: just stop.
- Events are emitted once, at the end. Intermediate reads only refresh "last good region", so a final read that fails still uses the last good one.

- [ ] **Step 1: Failing tests** with `FakeField` (a String buffer):
  - `learnsOnFinish`: begin on "x用 Orca 看", the user edits the buffer to "x用 rea 看", finish(.completionKey) → onEvents [.learn(Orca→rea)]
  - `finishOnReturnComparesFirst`: same; the edit happened, finish(.completionKey) then the buffer is cleared → still learned (finish reads before the caller passes Return on)
  - `anchorLostLearnsNothing`: the buffer is replaced entirely → []
  - `unreadableClientNoTracking`: `text(in:)` returns nil → begin is a no-op, finish emits nothing
  - `disabledNoTracking`: isEnabled false → nothing
  - `secureNoTracking`: isSecure true → nothing
  - `timeoutEnds`: now advances 61 s, keyHandled → events emitted once; later finish emits nothing
  - `throttledReads`: 10 keyHandled calls within 1 s → field read ≤ 2 times (FakeField counts reads)
  - `markedTextSkipsRead`: hasMarkedText true → keyHandled does not read
  - `newInsertionEndsPrevious`: begin A, begin B → events for A emitted first
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement per the Interfaces notes.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit: `CorrectionTracker：跟踪上屏后的修改`.

### Task 6: Wire into the input method, add the setting and docs

**Files:**
- Modify: `Shared/SharedSettings.swift`: `SettingKey.learnFromEdits = "learnFromEdits"`; `SharedSettings.learnFromEdits: Bool { bool(SettingKey.learnFromEdits, default: true) }`
- Create: `ErgouIME/Speech/CorrectionLearning.swift`:
  - `enum CorrectionLearning { static let tracker: CorrectionTracker; static func handle(_ events: [CorrectionEvent]) }`
  - `handle` maps events:
    - learn → `CorrectionStore.learn` + `TermStore.shared.record(term:, heard:, source: .edit)`;
    - hotword → `record(term:, heard: nil, source: .edit)`;
    - veto → `CorrectionStore.veto`.
  - Its `isSecure` is `{ SecureInput.isActive }`.
  - Also an `IMKTextInput` adapter `final class ClientField: CorrectionField` wrapping the client: `length()`, `attributedSubstring(from:)?.string`, `markedRange().length > 0`.
- Modify: `ErgouIME/Speech/VoiceSession.swift`:
  - in `deliver`, before AutoSpace: if `SharedSettings.learnFromEdits`, `let (fixed, applied) = EditCorrection.apply(text, rules: CorrectionStore.shared.rules)`, then `CorrectionStore.shared.used(applied)`;
  - pass `applied` to `target.insertVoiceText(_:applied:)`. History stores the fixed text.
- Modify: `VoiceTarget.insertVoiceText(_ text: String, applied: [CorrectionPair]) -> Bool` (protocol in VoiceSession.swift):
  - `ForeignInsert` calls it with `applied: []`, through a separate path that does not track: add a parameter `track: Bool`, false from ForeignInsert.
- Modify: `ErgouIME/Controller/ErgouInputController.swift`:
  - `insertVoiceText`:
    - `start = client.selectedRange().location`, after clearing marked text;
    - `let s = spaced(text, in: client)`; insert;
    - if `track`, `CorrectionLearning.tracker.begin(field: ClientField(client), start: start, inserted: s, applied: applied)`.
  - `handle(_:client:)`: right after the SecureInput check, for keyDown of Return, KeypadEnter, Tab or Escape with no marked text, call `tracker.finish(field: …, reason: .completionKey)` before anything else. After the key is processed (all return paths), call `tracker.keyHandled(field:)`. A `defer` is fine; the throttle keeps it cheap.
  - `deactivateServer`: `tracker.finish(field: ClientField(client), reason: .focusLost)` before clearing.
  - `ClientField` is created per call; its `identity` is `ObjectIdentifier(client as AnyObject)`.
- Modify: `ErgouIMESettings/Views/ModelSettingsView.swift`: in the 语音记录 section, add `Toggle` bound to `@AppStorage(SettingKey.learnFromEdits, store: Paths.sharedDefaults) var learnFromEdits = true`.
  - Title: 从我的修改里学习
  - Caption: 语音打出来后，你在同一个输入框里把一个词改成别的，二狗会记住，以后自动改对。只记“听成什么 → 改成什么”这一对词，存在输入法自己的目录里，不上传。学到的词在“我的词”里，可以删除。
- Modify: `PRIVACY.md`: add a row in 数据存在哪里:
  `| 从修改里学到的词对（可关闭） | ~/Library/Containers/com.codamon.inputmethod.Ergou/Data/Library/Application Support/ErgouIME/voice-corrections.json |`
  Add a sentence below it: what is read (the text around the voice result, in memory, for at most 60 s), what is stored (only word pairs), and that it never happens in password fields.
  Same addition in the English summary.
- Modify: `Shared/Privacy.swift`: append a rule line in the same style as the existing ones: corrections are learned on device only, from the inserted region only.

- [ ] **Step 1:** `scripts/test-swift.sh`. Expected: PASS (nothing in the tested files changed).
- [ ] **Step 2:** `./scripts/check-no-network.sh`. Expected: `ok`. Then `xcodegen generate -q && ./scripts/build-signed.sh` on the Mac (installs). Expected: build OK.
- [ ] **Step 3: Manual check on the Mac** (the user is at it; ask them to do the speaking parts):
  1. In TextEdit, dictate a sentence containing a term that gets misheard, fix that word by hand, then press Return.
     Expected: 设置 › 我的词 shows the term with "你改过 · 听成过：A".
  2. Dictate it again. Expected: B is typed directly.
  3. Change it back to A, then press Return. Then dictate it again. Expected: A is kept (vetoed).
  4. Turn the switch off and dictate. Expected: no replacement.
  Log lines: `Log.speech.notice("correction: learned N, vetoed M")` — counts only, never text.
- [ ] **Step 4:** Commit: `0.5：从用户的修改里学习——接入输入法、设置开关、隐私说明`.

### Task 7: Release notes draft

**Files:**
- Create: `docs/releases/v0.5.0.md` (same format as `docs/releases/v0.4.2.md`): what it does, how to turn it off, what is stored where, and that nothing is uploaded.

- [ ] **Step 1:** Write it. Commit: `发布说明 0.5.0 草稿`. (The version bump and release happen after the user has tested.)
