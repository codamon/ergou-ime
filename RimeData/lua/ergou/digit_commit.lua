-- ergou-ime — a digit that picks no candidate types the keys and the digit.
-- SPDX-License-Identifier: GPL-3.0-only
--
-- D, 2026-11-20: typing "mem" shows 5 candidates; 0 (never a candidate key,
-- pages hold 3–9) or 6–9 commits "mem0" … "mem9" as typed. librime's
-- selector accepts every digit while composing and does nothing when no
-- candidate sits behind it (librime 1.17.0 selector.cc SelectCandidateAt).
-- Digits that do pick a candidate are left to the selector.
--
-- Must run before selector and after recognizer: recognizer takes the
-- digits of a calculator input (=12*3) itself; inputs starting with "=" are
-- skipped here as well. The ` prefix (pinyin only / 拆字) is not typed.
-- What was already picked in a pinyin sentence stays: nihaoma with 你好
-- chosen, then 0, types 你好ma0. Typed with engine:commit_text, so 自动调频
-- records nothing.

local kAccepted, kNoop = 1, 2

local P = {}

-- 0–9 on the main row (0x30–0x39) or the keypad (XK_KP_0–9, 0xffb0–0xffb9).
local function digit(code)
  if code >= 0x30 and code <= 0x39 then return code - 0x30 end
  if code >= 0xffb0 and code <= 0xffb9 then return code - 0xffb0 end
  return nil
end

-- Candidates on the page that is showing now.
local function on_page(context, page_size)
  if not context:has_menu() then return 0 end
  local seg = context.composition:back()
  if not seg or not seg.menu then return 0 end
  local start = (seg.selected_index // page_size) * page_size
  local count = seg.menu:prepare(start + page_size)
  return math.max(0, math.min(page_size, count - start))
end

-- Picked segments as text, then the keys after them as typed.
local function typed_text(context)
  local input = context.input
  local picked, from = "", 0
  local ok, segs = pcall(function() return context.composition:toSegmentation():get_segments() end)
  if ok and segs then
    for _, seg in ipairs(segs) do
      if seg.status ~= "kSelected" and seg.status ~= "kConfirmed" then break end
      local cand = seg:get_selected_candidate()
      if not cand then break end
      picked, from = picked .. cand.text, seg._end
    end
  end
  return picked .. (input:sub(from + 1):gsub("^`", ""))
end

function P.func(key, env)
  if key:release() or key:ctrl() or key:alt() or key:super() then return kNoop end
  local d = digit(key.keycode)
  if d == nil then return kNoop end
  local context = env.engine.context
  if not context:is_composing() then return kNoop end
  local input = context.input
  if input == "" or input:sub(1, 1) == "=" then return kNoop end

  local page_size = env.engine.schema.page_size
  if not page_size or page_size < 1 then page_size = 5 end
  -- Digit n picks the n-th candidate; 0 picks none.
  if d >= 1 and d <= on_page(context, page_size) then return kNoop end

  env.engine:commit_text(typed_text(context) .. tostring(d))
  context:clear()
  return kAccepted
end

return P
