-- ergou-ime — optional "四码唯一自动上屏" for wubi + pinyin mixed input.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Off by default (ergou/auto_commit: false, D 2026-11-08): then this
-- processor does nothing and every candidate is picked with Space/digits.
--
-- When on (candidate order is the same as when off, see rank.lua):
--   * The 4th key is pushed here. If exactly one WUBI candidate covers the
--     4 keys (pinyin candidates are not counted), it is committed — unless
--     the 4 keys could still become pinyin ("shan" → "shang"); then it waits.
--   * 顶字 (like rime-wubi86-jidian's max_code_length: 4): with 4 keys typed
--     and wubi candidates present (unique or not, e.g. trnt = 我 / 特性), a 5th
--     key that cannot continue pinyin commits the FIRST wubi candidate and
--     starts the next code. A 5th key that keeps it pinyin carries on as
--     pinyin. Since almost any key can start a new syllable, codes that look
--     like pinyin mostly need Space (verified with librime on a Mac,
--     2026-11-09).
--     Space always commits the first candidate, which is wubi in this mode.
--   * ergou/auto_commit_strict: true ignores pinyin here: any unique 4-key
--     wubi code commits at once and a 5th key always 顶字 when there is a wubi
--     candidate; long pinyin then needs the ` prefix.
--
-- Commits go through context:select + context:commit (not engine:commit_text)
-- so that librime's user dictionary still records the choice (自动调频).
--
-- STATUS: never run. librime-lua API names (Menu:prepare,
-- Menu:get_candidate_at, Segment.menu, Context:select/commit/push_input)
-- follow librime-lua's documentation and must be checked on a Mac (M1.5).

local pinyin = require("ergou.pinyin")

local kRejected, kAccepted, kNoop = 0, 1, 2

local WUBI_TYPES = { table = true, user_table = true }

local P = {}

function P.init(env)
  local config = env.engine.schema.config
  env.enabled = config:get_bool("ergou/auto_commit") == true
  env.strict = config:get_bool("ergou/auto_commit_strict") == true
  env.py = pinyin.from_config(config)
end

-- Index of the first wubi candidate covering the whole input, and how many
-- there are (up to 2). Pinyin and correction candidates are not counted.
local function wubi_candidates(context)
  local segment = context.composition:back()
  if not segment or not segment.menu then return nil, 0 end
  local menu = segment.menu
  -- rank.lua puts exact wubi candidates first; 10 is plenty to see a
  -- second one if there is one.
  local count = menu:prepare(10)
  local first, wubi = nil, 0
  local seen = {}
  for i = 0, count - 1 do
    local cand = menu:get_candidate_at(i)
    -- uniquifier wraps duplicates (the exact and the completion wubi tables
    -- both return exact codes) as type "uniquified"; look at the original.
    local genuine = cand and cand:get_genuine()
    -- An emoji or symbol that simplifier@emoji put after a wubi word has
    -- that word as its original: one candidate, not two.
    if genuine and WUBI_TYPES[genuine.type] and cand._end == #context.input
       and not seen[genuine.text] then
      seen[genuine.text] = true
      wubi = wubi + 1
      first = first or i
      if wubi > 1 then break end
    end
  end
  return first, wubi
end

local function commit_index(context, index)
  context:select(index)
  if context:is_composing() then context:commit() end
end

local function is_letter(code)
  return code >= 0x61 and code <= 0x7a  -- a–z
end

function P.func(key, env)
  if not env.enabled then return kNoop end
  if key:release() or key:ctrl() or key:alt() or key:super() then return kNoop end
  local code = key.keycode
  if not is_letter(code) then return kNoop end

  local context = env.engine.context
  local input = context.input
  if input:find("[^a-z]") then return kNoop end  -- ` prefix, delimiters, …
  local ch = string.char(code)

  -- 5th key after a 4-key code: carry on as pinyin, or 顶字.
  if #input == 4 then
    if not env.strict and pinyin.is_prefix(input .. ch, env.py) then return kNoop end
    local first = wubi_candidates(context)
    if first == nil then return kNoop end
    commit_index(context, first)
    context:push_input(ch)  -- the key starts the next code
    return kAccepted
  end

  if #input ~= 3 then return kNoop end

  -- Push the 4th key ourselves so we can look at the result.
  context:push_input(ch)
  local first, count = wubi_candidates(context)
  if count == 1 and (env.strict or not pinyin.is_prefix(context.input, env.py)) then
    commit_index(context, first)
  end
  return kAccepted
end

return P
