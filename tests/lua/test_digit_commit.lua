-- SPDX-License-Identifier: GPL-3.0-only
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
local D = require("ergou.digit_commit")
local FAILED = false
local function expect(name, got, want) print((got == want and "ok  " or "FAIL"), name, got); if got ~= want then FAILED = true end end

-- o.count: candidates in the menu; o.page: page size; o.sel: highlighted index.
local function run(keycode, o)
  local committed, cleared = nil, false
  local ctx = { input = o.input }
  function ctx:is_composing() return self.input ~= "" end
  function ctx:has_menu() return (o.count or 0) > 0 end
  function ctx:clear() cleared = true end
  -- o.chosen: segments already picked, as { text, _end } (pinyin sentences).
  local segs = {}
  local at = 0
  for _, c in ipairs(o.chosen or {}) do
    segs[#segs + 1] = { status = "kSelected", start = at, _end = c[2],
      get_selected_candidate = function() return { text = c[1] } end }
    at = c[2]
  end
  segs[#segs + 1] = { status = "kGuess", start = at, _end = #o.input }
  ctx.composition = {
    back = function()
      return { selected_index = o.sel or 0,
        menu = { prepare = function(_, n) return math.min(n, o.count or 0) end } }
    end,
    toSegmentation = function() return { get_segments = function() return segs end } end,
  }
  local env = { engine = { context = ctx, commit_text = function(_, s) committed = s end,
    schema = { page_size = o.page or 5 } } }
  if D.init then D.init(env) end
  local key = { keycode = keycode, release = function() return o.release == true end,
    ctrl = function() return o.ctrl == true end, alt = function() return false end,
    super = function() return false end }
  local r = D.func(key, env)
  return r .. "|" .. tostring(committed) .. "|" .. tostring(cleared)
end
local function k(d) return 0x30 + d end

expect("0 is never a candidate: mem0", run(k(0), { input = "mem", count = 5 }), "1|mem0|true")
expect("6 with 5 candidates: mem6", run(k(6), { input = "mem", count = 5 }), "1|mem6|true")
expect("4 with 3 candidates on a 5 page", run(k(4), { input = "mem", count = 3 }), "1|mem4|true")
expect("3 with 5 candidates picks as before", run(k(3), { input = "mem", count = 5 }), "2|nil|false")
expect("5 with 5 candidates picks as before", run(k(5), { input = "mem", count = 5 }), "2|nil|false")
expect("9 on a full 9 page picks as before", run(k(9), { input = "mem", count = 20, page = 9 }), "2|nil|false")
expect("last page: 2 left, 3 is not there", run(k(3), { input = "mem", count = 7, sel = 5 }), "1|mem3|true")
expect("last page: 2 left, 2 picks", run(k(2), { input = "mem", count = 7, sel = 5 }), "2|nil|false")
expect("no candidates at all: typed with the digit", run(k(1), { input = "qqqq", count = 0 }), "1|qqqq1|true")
expect("keypad 0", run(0xffb0, { input = "mem", count = 5 }), "1|mem0|true")
expect("keypad 3 picks as before", run(0xffb3, { input = "mem", count = 5 }), "2|nil|false")
expect("` prefix is not typed", run(k(0), { input = "`niu", count = 5 }), "1|niu0|true")
expect("calculator input is left alone", run(k(0), { input = "=12", count = 1 }), "2|nil|false")
expect("not composing: not ours", run(k(0), { input = "" }), "2|nil|false")
expect("letters: not ours", run(0x61, { input = "mem", count = 5 }), "2|nil|false")
expect("key release: not ours", run(k(0), { input = "mem", count = 5, release = true }), "2|nil|false")
expect("with Control: not ours", run(k(0), { input = "mem", count = 5, ctrl = true }), "2|nil|false")
expect("what was chosen before is typed: 你好ma0",
  run(k(0), { input = "nihaoma", count = 5, chosen = { { "你好", 5 } } }), "1|你好ma0|true")
if FAILED then os.exit(1) end
