-- SPDX-License-Identifier: GPL-3.0-only
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
local C = require("ergou.calc")
local D = require("ergou.date")
local FAILED = false
local function expect(name, got, want) print((got == want and "ok  " or "FAIL"), name, tostring(got)); if got ~= want then FAILED = true end end
local function calc(s) local v = C.parse(s); return v and C.format(v) end
expect("precedence", calc("12*3.5+8"), "50")
expect("parentheses", calc("(1+2)*3"), "9")
expect("decimals", calc("10/4"), "2.5")
expect("power", calc("2^10"), "1024")
expect("negative", calc("-3+5"), "2")
expect("modulo", calc("10%3"), "1")
expect("spaces", calc(" 1 + 2 "), "3")
expect("division by zero", calc("1/0"), nil)
expect("garbage", calc("1+"), nil)
expect("no integer wrap", calc("3000000000*4000000000"), "12000000000000000000")
expect("unary minus below power", calc("-2^2"), "-4")
expect("negative exponent", calc("2^-1"), "0.5")
expect("letters rejected", calc("os.exit()"), nil)
local d = D.candidates("date", os.time({year=2026, month=11, day=9, hour=17, min=5}))
expect("date iso", d[1], "2026-11-09")
expect("date zh", d[2], "2026年11月9日")
expect("date weekday", d[3], "11月9日 星期一")
expect("full pinyin: sj is time", D.keys(false).sj, "time")
expect("shuangpin: sj is a syllable", D.keys(true).sj, nil)
expect("shuangpin: xq is a syllable", D.keys(true).xq, nil)
expect("shuangpin: time still works", D.keys(true).time, "time")
local denv = { engine = { schema = { config = { get_bool = function(_, k) return k == "ergou/shuangpin" or nil end } } } }
D.init(denv)
expect("init reads ergou/shuangpin", denv.keys.sj, nil)
denv.engine.schema.config.get_bool = function() return nil end
D.init(denv)
expect("no key: full pinyin keys", denv.keys.rq, "date")
expect("week", D.candidates("week", os.time({year=2026, month=11, day=9, hour=12}))[1], "星期一")
local P = require("ergou.phrases")
expect("unescape newline", P.unescape("a\\nb"), "a\nb")
expect("unescape backslash", P.unescape("c:\\\\x"), "c:\\x")
local tmp = os.tmpname()
local f = io.open(tmp, "w"); f:write("dz\t北京市朝阳区某某路 1 号\nsig\t张三\\n工程师\nbad line\n"); f:close()
local map = P.load(tmp); os.remove(tmp)
expect("load code", map.dz and map.dz[1], "北京市朝阳区某某路 1 号")
expect("load multiline", map.sig and map.sig[1], "张三\n工程师")
expect("skip bad line", map["bad line"], nil)
-- Reload only when the checksum line changes.
local dir = os.tmpname(); os.remove(dir)
local path = dir .. "/ergou_phrases.txt"
os.execute("mkdir -p '" .. dir .. "'")
local function put(s) local f = io.open(path, "w"); f:write(s); f:close() end
put("# aaa\ndz\t旧地址\n")
rime_api = { get_user_data_dir = function() return dir end }
local out = {}
function yield(c) out[#out + 1] = c end
function Candidate(t, s, e, text, comment) return { type = t, text = text, comment = comment } end
local penv = {}
P.init(penv)
expect("stamp is the first line", penv.stamp, "# aaa")
expect("first load", penv.map.dz[1], "旧地址")
local function query(code)
  out = {}
  penv.checked = -1                                 -- as if a second passed
  P.func(code, { start = 0, _end = #code, has_tag = function(_, t) return t == "abc" end }, penv)
  return out[1] and out[1].text
end
put("# aaa\ndz\t新地址\n")
expect("same checksum: not re-read", query("dz"), "旧地址")
put("# bbb\ndz\t新地址\n")
expect("new checksum: reloaded", query("dz"), "新地址")
os.remove(path); os.remove(dir)
expect("file gone: no phrases", query("dz"), nil)
if FAILED then os.exit(1) end
