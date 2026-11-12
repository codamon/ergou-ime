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
--   * 双拼: the keys split into two-key codes of the scheme in use
--     (lua/ergou/shuangpin_codes.lua, generated from the same algebra the
--     input method writes). Not by candidates: 双拼 correction and the
--     interjection n make sentences of English too (github → 过糖水).
--
-- The last choice wins (user request, 2026-11-12: a pinyin typer writes 问题
-- as "went" and 可以 as "key", which are not whole syllables, so the English
-- word was first every time, however often 问题 was picked). When the keys
-- of an English word are committed as Chinese, Chinese is first for those
-- keys from then on; when they are committed as the English word, English
-- is. Only choices against the rule above are kept, in
-- ergou_english_order.txt in the Rime user directory ("keys<TAB>zh|en", at
-- most MAX_KEPT lines, never the Chinese text). Off with 自动调频
-- (ergou/english_learning), deleted by 清空调频记录.
--
-- 中英混输 can be switched off in Settings: the input method then gives the
-- English translator a tag no segment has, and this filter sees no English.
--
-- English candidates are re-made as type "english", so lua/ergou/auto_commit
-- (which counts "table" candidates as wubi) never takes them for wubi, and
-- they carry no code hint. Only the first WINDOW candidates are looked at;
-- english has a high initial_quality, so the engine puts them in front.

local WINDOW = 60
local MAX_KEPT = 500

local pinyin = require("ergou.pinyin")
local shuangpin_codes = require("ergou.shuangpin_codes")


local function is_english(cand)
  return cand.text:find("^[A-Za-z]+$") ~= nil
end

local F = {}

-- ---- the last choice per keys -------------------------------------------

-- First line of the file: changes on every save, so other sessions (one per
-- app) notice without reading the whole file.
local function stamp(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  return line
end

local function load_order(path)
  local order, count = {}, 0
  local f = io.open(path, "r")
  if not f then return order, count end
  for line in f:lines() do
    local keys, choice = line:match("^([a-z]+)\t(%a%a)$")
    if keys and (choice == "zh" or choice == "en") and not order[keys] then
      order[keys] = choice
      count = count + 1
    end
  end
  f:close()
  return order, count
end

local function save_order(env)
  local f = io.open(env.order_path, "w")
  if not f then return end
  env.order_stamp = "# " .. os.time() .. " " .. math.random(1000000)
  f:write(env.order_stamp, "\n")
  for keys, choice in pairs(env.order) do f:write(keys, "\t", choice, "\n") end
  f:close()
end

local function reload_order(env)
  env.order_checked = os.time()
  local now = stamp(env.order_path)
  if now ~= env.order_stamp then
    env.order_stamp = now
    env.order, env.order_count = load_order(env.order_path)
  end
end

-- `text` was committed for the whole input `keys`; `shown` is what the
-- filter last put in front of the user for those keys.
function F.learn(env, keys, text)
  local shown = env.shown
  if not env.learning or not shown or shown.keys ~= keys then return end
  local choice
  if shown.english[text] then
    choice = "en"
  elseif text:find("[\128-\255]") then
    choice = "zh"
  else
    return                                   -- raw letters, digits: says nothing
  end
  reload_order(env)
  local keep = choice ~= shown.rule and choice or nil   -- only what the rule gets wrong
  if env.order[keys] == keep then return end
  if keep and not env.order[keys] then
    if env.order_count >= MAX_KEPT then env.order, env.order_count = {}, 0 end
    env.order_count = env.order_count + 1
  elseif not keep then
    env.order_count = env.order_count - 1
  end
  env.order[keys] = keep
  save_order(env)
end

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
  env.learning = config:get_bool("ergou/english_learning") ~= false
  env.order, env.order_count = {}, 0
  if env.learning and rime_api and rime_api.get_user_data_dir then
    env.order_path = rime_api.get_user_data_dir() .. "/ergou_english_order.txt"
    reload_order(env)
    local context = env.engine.context
    if context.commit_notifier then
      env.commit_connection = context.commit_notifier:connect(function(ctx)
        F.learn(env, ctx.input, ctx:get_commit_text())
      end)
    end
  else
    env.learning = false
  end
  env.wubi = env.engine.schema.schema_id == "ergou_wubi"
  if not env.wubi and config:get_bool("ergou/shuangpin") == true then
    -- Unknown scheme: every even-length run counts as 双拼 (English second).
    env.pairs = shuangpin_codes[config:get_string("ergou/shuangpin_scheme") or ""] or true
  else
    env.syllables = pinyin.build(fuzzy_ids(config), false)
  end
end

function F.fini(env)
  if env.commit_connection then env.commit_connection:disconnect() end
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
  local keys = env.engine.context.input:sub(first.start + 1, first._end)
  if env.pairs then
    clash = #keys % 2 == 0
    if clash and env.pairs ~= true then
      for i = 1, #keys, 2 do
        if not env.pairs[keys:sub(i, i + 1)] then clash = false; break end
      end
    end
  else
    clash = pinyin.is_complete(keys, env.syllables)
    if not clash and env.wubi then
      for _, cand in ipairs(chinese) do
        if WUBI_EXACT[cand.type] and same_keys(cand, first) then clash = true; break end
      end
    end
  end
  -- What the rule says, then what the user last chose for these keys.
  local rule = (clash and #chinese > 0) and "zh" or "en"
  if env.learning then
    if os.time() ~= env.order_checked then reload_order(env) end
    local words = {}
    for _, cand in ipairs(english) do words[cand.text] = true end
    env.shown = { keys = keys, rule = rule, english = words }
  end
  local chosen = env.order[keys]
  local chinese_first = #chinese > 0 and (chosen == "zh" or (chosen ~= "en" and rule == "zh"))
  local function english_out()
    for _, cand in ipairs(english) do
      yield(Candidate("english", cand.start, cand._end, cand.text, ""))
    end
  end
  if chinese_first then
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
