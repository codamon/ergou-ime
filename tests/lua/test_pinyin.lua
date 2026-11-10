-- SPDX-License-Identifier: GPL-3.0-only
package.path = (os.getenv("ERGOU_LUA_DIR") or "RimeData/lua") .. "/?.lua;" .. package.path
local py = require("ergou.pinyin")
local d = py.build({"zh_z","ch_c","sh_s","n_l","en_eng","in_ing"}, true)
local plain = py.build({}, false)
local function check(name, got, want) print((got==want and "ok  " or "FAIL"), name, tostring(got)) ; if got~=want then FAILED=true end end
check("prefix shan", py.is_prefix("shan", plain), true)
check("prefix trnt", py.is_prefix("trnt", plain), false)
check("complete shang", py.is_complete("shang", plain), true)
check("complete shan", py.is_complete("shan", plain), true)
check("complete zhongguo", py.is_complete("zhongguo", plain), true)
check("prefix zhongg", py.is_prefix("zhongg", plain), true)
check("complete zongguo (no fuzzy)", py.is_complete("zongguo", plain), true) -- zong is a real syllable
check("complete zhang fuzzy zang", py.is_complete("zang", d), true)
check("complete shagn typo", py.is_complete("shagn", d), true)
check("complete shagn no typo", py.is_complete("shagn", plain), false)
check("complete xaing typo", py.is_complete("xaing", d), true)
check("complete lve", py.is_complete("lve", plain), true)
check("prefix with quote", py.is_prefix("xi'an", plain), true)
check("prefix kkkk", py.is_prefix("kkkk", plain), false)
-- wubi correction variants (copy of function)
if FAILED then os.exit(1) end
