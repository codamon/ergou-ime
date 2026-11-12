-- SPDX-License-Identifier: GPL-3.0-only
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
local S = require("ergou.select_character")
local FAILED = false
local function expect(name, got, want) print((got == want and "ok  " or "FAIL"), name, got); if got ~= want then FAILED = true end end

-- A context like librime-lua's: `whole` is what get_commit_text returns.
local function run(keycode, o)
  local committed, pushed, cleared = nil, nil, false
  local ctx = { input = o.input, caret_pos = o.caret or #o.input }
  function ctx:has_menu() return o.cand ~= nil end
  function ctx:get_selected_candidate() return o.cand and { text = o.cand } end
  function ctx:get_commit_text() return o.whole or o.cand end
  function ctx:clear() cleared = true end
  function ctx:push_input(s) pushed = s end
  local env = { engine = { context = ctx, commit_text = function(_, s) committed = s end,
    schema = { config = { get_bool = function(_, k) return o.enabled end } } } }
  S.init(env)
  local key = { keycode = keycode, release = function() return o.release == true end,
    ctrl = function() return o.ctrl == true end, alt = function() return false end, super = function() return false end }
  local r = S.func(key, env)
  return r .. "|" .. tostring(committed) .. "|" .. tostring(pushed) .. "|" .. tostring(cleared)
end
local L, R = 0x5b, 0x5d

expect("] takes the last character", run(R, { input = "chenmo", cand = "沉默" }), "1|默|nil|true")
expect("[ takes the first character", run(L, { input = "chenmo", cand = "沉默" }), "1|沉|nil|true")
expect("one character: typed as it is", run(L, { input = "ni", cand = "你" }), "1|你|nil|true")
expect("keys after the candidate stay", run(R, { input = "chenmoshijin", cand = "沉默", whole = "沉默shijin" }), "1|默|shijin|true")
expect("what was chosen before is typed too", run(R, { input = "woxihuanchenmo", cand = "沉默", whole = "我喜欢沉默" }), "1|我喜欢默|nil|true")
expect("the same word twice: the later one", run(R, { input = "x", cand = "沉默", whole = "沉默沉默" }), "1|沉默默|nil|true")
expect("keys right of the caret stay", run(L, { input = "chenmoab", caret = 6, cand = "沉默", whole = "沉默" }), "1|沉|ab|true")
expect("English word: the key does its own job", run(L, { input = "github", cand = "GitHub" }), "2|nil|nil|false")
expect("emoji: the key does its own job", run(R, { input = "xiao", cand = "😄" }), "2|nil|nil|false")
expect("symbol: the key does its own job", run(R, { input = "jiantou", cand = "→" }), "2|nil|nil|false")
expect("mixed ending: not ours", run(R, { input = "x", cand = "T恤A" }), "2|nil|nil|false")
expect("no candidates: not ours", run(L, { input = "" }), "2|nil|nil|false")
expect("other keys: not ours", run(0x61, { input = "chenmo", cand = "沉默" }), "2|nil|nil|false")
expect("key release: not ours", run(L, { input = "chenmo", cand = "沉默", release = true }), "2|nil|nil|false")
expect("with Control: not ours", run(L, { input = "chenmo", cand = "沉默", ctrl = true }), "2|nil|nil|false")
expect("turned off in Settings", run(L, { input = "chenmo", cand = "沉默", enabled = false }), "2|nil|nil|false")
expect("rare character (Extension B)", run(R, { input = "x", cand = "牛𤛭" }), "1|𤛭|nil|true")
if FAILED then os.exit(1) end
