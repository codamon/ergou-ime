-- ergou-ime — wubi typo correction, only for empty codes.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Wubi codes are dense: almost every 2–4 key string is a valid code, so
-- correcting a valid code would flood the menu. We only step in when the
-- keys are certainly wrong: no wubi entry for them and not pinyin either.
-- Then we try
--   1. swapping two neighbouring keys      (tnrt → trnt)
--   2. replacing one key by a QWERTY neighbour (trbt → trnt)
-- and offer at most 5 hits, marked "纠 <code>", ranked last. They are type
-- "correction": never auto-committed, never used for 顶字.
--
-- Option ergou/wubi_correction (Settings: 五笔容错), default on.
--
-- STATUS: never run. Check Memory:dict_lookup / iter_dict on a Mac (M1.5).

local pinyin = require("ergou.pinyin")

-- Wubi uses a–y. Same-row neighbours plus the keys diagonally above/below.
local NEIGHBOURS = {
  q = "wa",     w = "qesa",   e = "wrds",   r = "etfd",   t = "rygf",
  y = "tuhg",   u = "yijh",   i = "uokj",   o = "ipkl",   p = "ol",
  a = "qswz",   s = "awdexz", d = "serfxc", f = "drtgcv", g = "ftyhvb",
  h = "gyujbn", j = "huiknm", k = "jiolm",  l = "kop",
  x = "sdc",    c = "xdfv",   v = "cfgb",   b = "vghn",   n = "bhjm",
  m = "njk",
}

local MAX_RESULTS = 5

local T = {}

function T.init(env)
  local config = env.engine.schema.config
  local on = config:get_bool("ergou/wubi_correction")
  env.enabled = on == nil or on
  env.memory = Memory(env.engine, env.engine.schema)  -- translator/ = wubi86_jidian
  env.py = pinyin.from_config(config)
end

local function lookup(memory, code)
  local out = {}
  if memory:dict_lookup(code, false, 3) then
    for entry in memory:iter_dict() do out[#out + 1] = entry.text end
  end
  return out
end

local function variants(code)
  local list, seen = {}, { [code] = true }
  local function add(v)
    if not seen[v] then seen[v] = true; list[#list + 1] = v end
  end
  for i = 1, #code - 1 do
    add(code:sub(1, i - 1) .. code:sub(i + 1, i + 1) .. code:sub(i, i) .. code:sub(i + 2))
  end
  for i = 1, #code do
    local near = NEIGHBOURS[code:sub(i, i)] or ""
    for k in near:gmatch(".") do
      add(code:sub(1, i - 1) .. k .. code:sub(i + 1))
    end
  end
  return list
end

function T.func(input, segment, env)
  if not env.enabled or not segment:has_tag("abc") then return end
  if #input < 2 or #input > 4 or input:find("[^a-y]") then return end
  if #lookup(env.memory, input) > 0 then return end        -- not an empty code
  if pinyin.is_complete(input, env.py) then return end      -- pinyin will answer

  local shown, count = {}, 0
  for _, v in ipairs(variants(input)) do
    for _, text in ipairs(lookup(env.memory, v)) do
      if not shown[text] then
        shown[text] = true
        local cand = Candidate("correction", segment.start, segment._end, text, "纠 " .. v)
        cand.quality = -100
        yield(cand)
        count = count + 1
        if count >= MAX_RESULTS then return end
      end
    end
  end
end

return T
