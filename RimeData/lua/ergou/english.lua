-- ergou-ime — 中英混输: where English words go in the candidate list.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- table_translator@english looks the whole input up in ergou_en (exact
-- words only, standard spelling: python → Python). This filter decides the
-- place (D, 2026-11-11):
--   * no Chinese candidate covers the same keys (github, python, linux):
--     the English word is FIRST, so Space commits it;
--   * a Chinese candidate does (五笔 json = 果断, 拼音 node, women): the first
--     Chinese candidate stays first and the English word is SECOND.
-- When does Chinese "have the same keys"? Not by whatever the engine
-- offers: with initials and typo correction it makes a sentence of almost
-- anything (拼音 github → 骨头湖北, "gi t hu b"; 五笔混输 hello → 和嗯咯 via
-- 嗯 + fuzzy n=l).
--   * 拼音 (全拼): the keys are whole pinyin syllables, fuzzy pairs included,
--     typo spellings not (lua/ergou/pinyin.lua).
--   * 五笔拼音混输: the same, or a wubi entry whose code is exactly the keys
--     (json = 果断, go = 来).
--   * 双拼: a non-English candidate spans the same keys (双拼 has no
--     initials, so that is a real match), except corrections.
--
-- English candidates are re-made as type "english", so lua/ergou/auto_commit
-- (which counts "table" candidates as wubi) never takes them for wubi, and
-- they carry no code hint. Only the first WINDOW candidates are looked at;
-- english has a high initial_quality, so the engine puts them in front.

local WINDOW = 60

local pinyin = require("ergou.pinyin")

local GUESS = { correction = true }

local function is_english(cand)
  return cand.text:find("^[A-Za-z]+$") ~= nil
end

local F = {}

local function fuzzy_ids(config)
  local ids = {}
  local list = config:get_list("ergou/fuzzy")
  if list then
    for i = 0, list.size - 1 do
      local v = list:get_value_at(i)
      if v then ids[#ids + 1] = v.value end
    end
  end
  return ids
end

function F.init(env)
  local config = env.engine.schema.config
  env.wubi = env.engine.schema.schema_id == "ergou_wubi"
  if env.wubi or config:get_bool("ergou/shuangpin") ~= true then
    env.syllables = pinyin.build(fuzzy_ids(config), false)
  end
end

local WUBI_EXACT = { table = true, user_table = true }

local function same_keys(a, b) return a.start == b.start and a._end == b._end end

local function flush(list, env)
  local english, chinese = {}, {}
  for _, cand in ipairs(list) do
    if is_english(cand) then english[#english + 1] = cand else chinese[#chinese + 1] = cand end
  end
  if #english == 0 then
    for _, cand in ipairs(list) do yield(cand) end
    return
  end
  local first = english[1]
  local clash = false
  if env.syllables then
    local keys = env.engine.context.input:sub(first.start + 1, first._end)
    clash = pinyin.is_complete(keys, env.syllables)
    if not clash and env.wubi then
      for _, cand in ipairs(chinese) do
        if WUBI_EXACT[cand.type] and same_keys(cand, first) then clash = true; break end
      end
    end
  else
    for _, cand in ipairs(chinese) do
      if not GUESS[cand.type] and same_keys(cand, first) then clash = true; break end
    end
  end
  local function english_out()
    for _, cand in ipairs(english) do
      yield(Candidate("english", cand.start, cand._end, cand.text, ""))
    end
  end
  if clash then
    yield(chinese[1])
    english_out()
    for i = 2, #chinese do yield(chinese[i]) end
  else
    english_out()
    for _, cand in ipairs(chinese) do yield(cand) end
  end
end

function F.func(input, env)
  local list = {}
  local flushed = false
  for cand in input:iter() do
    if flushed then
      yield(cand)
    else
      list[#list + 1] = cand
      if #list >= WINDOW then
        flush(list, env)
        flushed = true
      end
    end
  end
  if not flushed then flush(list, env) end
end

return F
