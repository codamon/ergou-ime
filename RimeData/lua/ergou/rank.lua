-- ergou-ime — candidate order for wubi + pinyin mixed input.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Same order in both modes (D, 2026-11-09):
--   1. wubi entries whose code is exactly what was typed  (table, user_table)
--   2. pinyin                                              (everything else)
--   3. wubi entries whose code is longer than what was typed (completion)
--   4. wubi corrections                                    (correction)
-- Inside each group the engine's own order is kept, except that exact wubi
-- entries are sorted by how often each was picked in total (see picks()).
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

-- 调频 for exact wubi codes (D, 2026-11-20). librime orders user-dictionary
-- entries by a recency weight that forgets after about 200 commits
-- (librime 1.17.0 algo/dynamics.h: dee decays by exp(-ticks/200); the total
-- count enters formula_p only as commits/tick, which is negligible). On D's
-- Mac 去 (fcu) had been picked 128 times and 云 13, yet each 云 pick put 云
-- first and 去 needed 7–8 picks to come back. 五笔 is typed by position, so
-- the long-term count decides; the engine's order (recency, then the code
-- table) only breaks ties. Table entries never picked count as 0, so a picked
-- word still comes before them, as before.
local function picks(cand)
  local ok, n = pcall(function()
    local g = cand.get_genuine and cand:get_genuine() or cand
    local p = g:to_phrase()
    return p and p.entry and p.entry.commit_count
  end)
  return (ok and type(n) == "number" and n > 0) and n or 0
end

-- Stable sort by picks, only among candidates that cover the same input
-- (same _end): a shorter match is a different choice, not a reordering.
local function by_picks(list)
  local runs, order = {}, {}
  for i, c in ipairs(list) do
    local k = c._end or 0
    if not runs[k] then runs[k] = {}; order[#order + 1] = k end
    local r = runs[k]
    r[#r + 1] = { c = c, n = picks(c), i = i }
  end
  local result = {}
  for _, k in ipairs(order) do
    local r = runs[k]
    table.sort(r, function(a, b)
      if a.n ~= b.n then return a.n > b.n end
      return a.i < b.i
    end)
    for _, x in ipairs(r) do result[#result + 1] = x.c end
  end
  return result
end

local F = {}

local function flush(buckets)
  buckets[1] = by_picks(buckets[1])
  for _, b in ipairs(buckets) do for _, c in ipairs(b) do yield(c) end end
end

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
        flush(buckets)
        rest = true
      end
      yield(cand)
    end
  end
  if not rest then flush(buckets) end
end

return F
