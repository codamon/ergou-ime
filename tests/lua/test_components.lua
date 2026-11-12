-- SPDX-License-Identifier: GPL-3.0-only
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
-- ---- mocks of librime-lua globals ----
local DICT = { trnt = {"我"}, khlg = {"中国"}, shan = {"山?"}, aaaa={"工"}, ggll={"一"} }
function Memory() return {
  _r = nil,
  dict_lookup = function(self, code) self._r = DICT[code]; return self._r ~= nil end,
  iter_dict = function(self) local i=0; local r=self._r or {}; return function() i=i+1; if r[i] then return {text=r[i]} end end end,
} end
local out = {}
function yield(c) out[#out+1]=c end
function Candidate(t, s, e, text, comment) return {type=t, text=text, comment=comment} end
local function cfg(t) return {
  get_bool=function(_,k) return t[k] end,
  get_list=function(_,k) local l=t[k]; if not l then return nil end; return {size=#l, get_value_at=function(_,i) return {value=l[i+1]} end} end,
} end
local env = {engine={schema={config=cfg({["ergou/fuzzy"]={"zh_z"}})}}}
local W = require("ergou.wubi_correction")
W.init(env)
local seg = {start=0,_end=4,has_tag=function(_,t) return t=="abc" end}
local FAILED = false
local function expect(name, got, want) print((got == want and "ok  " or "FAIL"), name, got); if got ~= want then FAILED = true end end
local function run(code) out = {}; W.func(code, seg, env); local r = {} for _, c in ipairs(out) do r[#r + 1] = c.text .. "(" .. c.comment .. ")" end; return table.concat(r, " ") end
expect("swap tnrt", run("tnrt"), "我(纠 trnt)")
expect("neighbour trbt", run("trbt"), "我(纠 trnt)")
expect("valid code trnt", run("trnt"), "")
expect("valid code shan", run("shan"), "")
expect("neighbour kjlg", run("kjlg"), "中国(纠 khlg)")
expect("z is never wubi", run("zhan"), "")
-- ---- auto_commit with a mock context ----
local AC = require("ergou.auto_commit")
local function make(cands_by_input, strict)
  local committed = {}
  local ctx = { input = "" }
  function ctx:push_input(ch) self.input = self.input .. ch end
  function ctx:select(i) self.sel = i end
  function ctx:is_composing() return self.input ~= "" end
  function ctx:commit() committed[#committed+1] = cands_by_input[self.input][self.sel+1].text; self.input = "" end
  ctx.composition = { back = function()
    local list = cands_by_input[ctx.input] or {}
    return { menu = { prepare = function(_, n) return #list end, get_candidate_at = function(_, i) local c=list[i+1]; c._end = #ctx.input; c.get_genuine = c.get_genuine or function(self) return self.genuine or self end; return c end } }
  end }
  local e = { engine = { context = ctx, schema = { config = cfg({["ergou/auto_commit"]=true, ["ergou/auto_commit_strict"]=strict}) } } }
  AC.init(e)
  local function key(ch) return { keycode = string.byte(ch), release=function() return false end, ctrl=function() return false end, alt=function() return false end, super=function() return false end } end
  return function(s) for ch in s:gmatch(".") do local r = AC.func(key(ch), e); if r == 2 then ctx.input = ctx.input .. ch end end; return table.concat(committed, ","), ctx.input end
end
local C = {
  trnt = { {type="table", text="我"} },
  shan = { {type="table", text="山X"}, {type="phrase", text="山"} },
  ggll = { {type="table", text="一"}, {type="table", text="一二"} },
  -- uniquifier output: wubi underneath a "uniquified" wrapper
  hhgg = { {type="uniquified", text="上", genuine={type="table", text="上"}} },
}
local function both(c, i) return c .. "|" .. i end
expect("unique, not pinyin: commit", both(make(C)("trnt")), "我|")
expect("pinyin prefix: wait, shang stays pinyin", both(make(C)("shang")), "|shang")
expect("shanx is still pinyin (shan + xi…)", both(make(C)("shanx")), "|shanx")
expect("strict: commit at once", both(make(C, true)("shan")), "山X|")
expect("two wubi candidates: no commit", both(make(C)("ggll")), "|ggll")
expect("顶字: 5th key that is not pinyin commits first wubi", both(make(C)("ggllk")), "一|k")
expect("顶字 in strict mode ignores pinyin", both(make(C, true)("shangx")), "山X|gx")
-- ---- rank ----
local R = require("ergou.rank")
local function ranked(list)
  out = {}
  R.func({ iter = function() local i = 0; return function() i = i + 1; return list[i] end end })
  local r = {} for _, c in ipairs(out) do r[#r + 1] = c.text end; return table.concat(r, " ")
end
expect("rank: exact wubi, pinyin, completion, correction", ranked({
  {type="phrase", text="按"}, {type="completion", text="艺"}, {type="table", text="世"},
  {type="correction", text="纠"}, {type="user_phrase", text="安"}, {type="user_table", text="工"},
}), "世 工 按 安 艺 纠")
expect("uniquified wubi still counts", both(make(C)("hhgg")), "上|")
-- simplifier@emoji adds 🇨🇳 after 中国: its original is the same wubi candidate.
C.khlg = { {type="table", text="中国"}, {type="simplified", text="🇨🇳", genuine={type="table", text="中国"}} }
expect("an emoji after the only wubi candidate: still unique", both(make(C)("khlg")), "中国|")
if FAILED then os.exit(1) end
