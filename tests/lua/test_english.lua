-- SPDX-License-Identifier: GPL-3.0-only
-- lua/ergou/english.lua: where English words go (中英混输).
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
local out = {}
function yield(c) out[#out + 1] = c end
function Candidate(t, s, e, text, comment) return { type = t, start = s, _end = e, text = text, comment = comment } end
local E = require("ergou.english")
local FAILED = false
local function expect(name, got, want)
  print((got == want and "ok  " or "FAIL"), name, got)
  if got ~= want then FAILED = true end
end
-- c("table", "果断", 4): candidate of the given type spanning keys 0..len
local function c(t, text, len, start) return { type = t, text = text, start = start or 0, _end = len, comment = "x" } end
local function cfg(t) return {
  get_bool = function(_, k) return t[k] end,
  get_string = function(_, k) return t[k] end,
  get_list = function(_, k) local l = t[k]; if not l then return nil end
    return { size = #l, get_value_at = function(_, i) return { value = l[i + 1] } end } end,
} end
local function make_env(schema_id, values, input)
  local env = { engine = { schema = { schema_id = schema_id, config = cfg(values) }, context = { input = input or "" } } }
  E.init(env)
  return env
end
local WUBI = make_env("ergou_wubi", { ["ergou/fuzzy"] = { "n_l" } })
local env = WUBI
local function run(list)
  out = {}
  E.func({ iter = function() local i = 0; return function() i = i + 1; return list[i] end end }, env)
  local r = {}
  for _, x in ipairs(out) do r[#r + 1] = x.text .. (x.type == "english" and "*" or "") end
  return table.concat(r, " ")
end

local function wubi(input) WUBI.engine.context.input = input; env = WUBI end
wubi("github")
expect("no Chinese: English first", run({ c("phrase", "给", 2), c("table", "GitHub", 6) }), "GitHub* 给")
wubi("python")
expect("only English", run({ c("table", "Python", 6) }), "Python*")
wubi("json")
expect("wubi exact code clashes: second", run({ c("table", "GitHub", 4), c("table", "果断", 4), c("table", "果", 4) }), "果断 GitHub* 果")
wubi("women")
expect("pinyin syllables clash: second", run({ c("sentence", "我们", 5), c("table", "women", 5), c("phrase", "我", 2) }), "我们 women* 我")
wubi("linux")
expect("partial pinyin does not clash", run({ c("phrase", "你", 2), c("table", "linux", 5) }), "linux* 你")
wubi("rust")
expect("unfinished wubi code does not clash", run({ c("completion", "某", 4), c("table", "rust", 4) }), "rust* 某")
wubi("python")
expect("correction does not clash", run({ c("correction", "纠", 6), c("table", "Python", 6) }), "Python* 纠")
expect("no English: unchanged", run({ c("table", "工", 1), c("phrase", "啊", 1) }), "工 啊")
wubi("app")
expect("wubi table's own English entry counts as English", run({ c("table", "app", 3), c("table", "App", 3) }), "app* App*")
expect("English comment dropped", (function() run({ c("table", "Python", 6) }); return out[1].comment end)(), "")
-- beyond the window: later candidates pass through untouched
wubi("hello")
expect("五笔 hello: he + 嗯(l) pinyin sentence is not a clash",
  run({ c("phrase", "和嗯咯", 5), c("table", "hello", 5) }), "hello* 和嗯咯")
wubi("go")
local long = {}
for i = 1, 70 do long[#long + 1] = c("phrase", "字" .. i, 2) end
long[3] = c("table", "Go", 2)
long[1] = c("table", "来", 2)
local got = run(long)
expect("window: clash with 来, Go second", got:sub(1, #"来 Go* 字2 字4"), "来 Go* 字2 字4")

-- 全拼 (ergou_pinyin_ime): whole pinyin syllables decide, not the engine's
-- candidates (with initials it makes "骨头湖北" of github).
local function quanpin(input, values)
  env = make_env("ergou_pinyin_ime", values or { ["ergou/fuzzy"] = { "zh_z", "n_l" } }, input)
  return env
end
quanpin("github")
expect("全拼 github: initials sentence ignored, English first",
  run({ c("sentence", "骨头湖北", 6), c("table", "GitHub", 6) }), "GitHub* 骨头湖北")
quanpin("women")
expect("全拼 women: whole syllables, English second",
  run({ c("sentence", "我们", 5), c("table", "women", 5) }), "我们 women*")
quanpin("python")
expect("全拼 python: not pinyin", run({ c("sentence", "爬", 6), c("table", "Python", 6) }), "Python* 爬")
quanpin("lanai")
expect("全拼 fuzzy n_l counts (la + nai)", run({ c("sentence", "拉奶", 5), c("table", "lanai", 5) }), "拉奶 lanai*")
quanpin("shagn", { ["ergou/fuzzy"] = {} })
expect("全拼 typo spellings do not count", run({ c("sentence", "上", 5), c("table", "shagn", 5) }), "shagn* 上")
-- 双拼: the keys must split into the scheme's two-key codes (小鹤: wo mf =
-- 我们, go = guo; gi th ub is not 双拼), whatever the engine offers.
local function sp(input, scheme)
  env = make_env("ergou_pinyin_ime", { ["ergou/shuangpin"] = true, ["ergou/shuangpin_scheme"] = scheme or "xiaohe" }, input)
end
sp("go")
expect("双拼 go = guo: second", run({ c("phrase", "过", 2), c("table", "go", 2) }), "过 go*")
sp("github")
expect("双拼 github: correction sentence ignored, first", run({ c("sentence", "过糖水", 6), c("table", "GitHub", 6) }), "GitHub* 过糖水")
sp("linux")
expect("双拼 odd length: first", run({ c("sentence", "里嗯刷", 5), c("table", "Linux", 5) }), "Linux* 里嗯刷")
sp("womf")
expect("双拼 wo mf: second", run({ c("phrase", "我们", 4), c("table", "womf", 4) }), "我们 womf*")
sp("python", "ziranma")
expect("自然码 py th on: on is not a code, first", run({ c("sentence", "平", 6), c("table", "Python", 6) }), "Python* 平")
sp("go", "unknown")
expect("unknown scheme: even length counts as 双拼", run({ c("phrase", "过", 2), c("table", "go", 2) }), "过 go*")
sp("go")
expect("clash but no Chinese candidate: English only", run({ c("table", "go", 2) }), "go*")
env = WUBI

-- The last choice wins (ergou_english_order.txt). A user data directory and
-- a commit notifier make the filter learn; commit(text) is the user
-- committing `text` for the whole input.
local dir = os.tmpname()
os.remove(dir)
os.execute("mkdir -p " .. dir)
rime_api = { get_user_data_dir = function() return dir end }
local function learner(input, values)
  values = values or { ["ergou/fuzzy"] = { "zh_z", "n_l" } }
  local e = { engine = { schema = { schema_id = "ergou_pinyin_ime", config = cfg(values) }, context = { input = input } } }
  e.engine.context.commit_notifier = { connect = function(_, fn)
    e.committed = fn
    return { disconnect = function() e.committed = nil end }
  end }
  E.init(e)
  return e
end
local function commit(e, text)
  e.committed({ input = e.engine.context.input, get_commit_text = function() return text end })
end
local function file()
  local f = io.open(dir .. "/ergou_english_order.txt", "r")
  if not f then return "" end
  local lines = {}
  f:read("*l")                                 -- the stamp
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  table.sort(lines)
  return table.concat(lines, "|")
end
local went = function() return { c("table", "went", 4), c("phrase", "问题", 4), c("phrase", "文体", 4) } end
env = learner("went")
expect("went = wen + t: not whole syllables, English first", run(went()), "went* 问题 文体")
commit(env, "问题")
expect("picked 问题: Chinese first from now on", run(went()), "问题 went* 文体")
expect("kept as keys and zh only", file(), "went\tzh")
local other = learner("went")
env = other
expect("another app's session reads it", run(went()), "问题 went* 文体")
commit(env, "went")
expect("picked went: English first again", run(went()), "went* 问题 文体")
expect("back to the rule: nothing kept", file(), "")
env = learner("women")
local women = function() return { c("sentence", "我们", 5), c("table", "women", 5) } end
expect("women: whole syllables, Chinese first", run(women()), "我们 women*")
commit(env, "women")
expect("picked women: English first", run(women()), "women* 我们")
expect("kept", file(), "women\ten")
commit(env, "我们")
expect("picked 我们: Chinese first again, nothing kept", run(women()) .. "/" .. file(), "我们 women*/")
env = learner("went")
run(went())
env.engine.context.input = "wentile"
commit(env, "问题了")
env.engine.context.input = "went"
expect("a commit for other keys teaches nothing", run(went()), "went* 问题 文体")
commit(env, "1234")
expect("digits teach nothing", file(), "")
env = learner("went", { ["ergou/fuzzy"] = {}, ["ergou/english_learning"] = false })
run(went())
expect("自动调频 off: no notifier, no file", tostring(env.committed) .. file(), "nil")
env = learner("went")
run(went()); commit(env, "问题")
env = learner("went", { ["ergou/fuzzy"] = {}, ["ergou/english_learning"] = false })
expect("自动调频 off: what was kept is not used either", run(went()), "went* 问题 文体")
os.execute("rm -rf " .. dir)
rime_api = nil
env = WUBI
if FAILED then os.exit(1) end
