-- ergou-ime — in pinyin mode, show date/time candidates after the first word.
-- SPDX-License-Identifier: GPL-3.0-only
--
--   riqi → 日期, 2026-11-09, 2026年11月9日, …   (not the dates before 日期)

local F = {}

function F.func(input)
  local held = {}
  local first_done = false
  for cand in input:iter() do
    if not first_done and cand.type == "date" then
      held[#held + 1] = cand
    else
      yield(cand)
      if not first_done then
        first_done = true
        for _, d in ipairs(held) do yield(d) end
        held = {}
      end
    end
  end
  for _, d in ipairs(held) do yield(d) end
end

return F
