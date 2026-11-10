-- ergou-ime — candidate order for wubi + pinyin mixed input.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Same order in both modes (D, 2026-11-09):
--   1. wubi entries whose code is exactly what was typed  (table, user_table)
--   2. pinyin                                              (everything else)
--   3. wubi entries whose code is longer than what was typed (completion)
--   4. wubi corrections                                    (correction)
-- Inside each group the engine's own order (frequency) is kept.
--
-- Why: tested with librime 1.17.0 on a Mac (2026-11-09), ranking purely by
-- quality let pinyin bury short wubi codes (an/de/ni/ge showed only pinyin on
-- page 1), while demoting pinyin below everything buried 我 under unfinished
-- wubi codes when typing "wo". "四码唯一自动上屏" no longer changes the order;
-- it only adds auto-commit and 顶字 (lua/ergou/auto_commit.lua).
--
-- The engine already emits this order (ergou_wubi splits wubi into an exact
-- table with high quality and a completion table with low quality); this
-- filter only fixes up the first WINDOW candidates, e.g. corrections. It
-- must not be relied on to find candidates further down: "e" has 100+
-- pinyin characters before any completion (D's Mac, 2026-11-09).

local WINDOW = 60

local function group(cand)
  local t = cand.type
  if t == "table" or t == "user_table" then return 1 end
  if t == "completion" then return 3 end
  if t == "correction" then return 4 end
  return 2
end

local F = {}

function F.func(input)
  local buckets = { {}, {}, {}, {} }
  local n = 0
  local rest = nil
  for cand in input:iter() do
    if n < WINDOW then
      local b = buckets[group(cand)]
      b[#b + 1] = cand
      n = n + 1
    else
      if not rest then
        for _, b in ipairs(buckets) do for _, c in ipairs(b) do yield(c) end end
        rest = true
      end
      yield(cand)
    end
  end
  if not rest then
    for _, b in ipairs(buckets) do for _, c in ipairs(b) do yield(c) end end
  end
end

return F
